#==============================================================================
# Copyright (C) 2021-present Alces Flight Ltd.
#
# This file is part of Flight Job.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# Flight Job is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with Flight Job. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on Flight Job, please visit:
# https://github.com/openflighthpc/flight-job
#==============================================================================

require 'json'
require 'securerandom'
require 'json_schemer'
require 'time'
require 'open3'

module FlightJob
  class Job < ApplicationModel
    PENDING_STATES = ['PENDING']
    TERMINAL_STATES = ['FAILED', 'COMPLETED', 'CANCELLED', 'UNKNOWN']
    RUNNING_STATES = ['RUNNING']
    STATES = [*PENDING_STATES, *RUNNING_STATES, *TERMINAL_STATES]

    STATES_LOOKUP = {}.merge(PENDING_STATES.map { |s| [s, :pending] }.to_h)
                      .merge(RUNNING_STATES.map { |s| [s, :running] }.to_h)
                      .merge(TERMINAL_STATES.map { |s| [s, :terminal] }.to_h)

    SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["created_at", "script_id", "state", "submit_status", "submit_stdout", "submit_stderr"],
      "properties" => {
        # ----------------------------------------------------------------------------
        # Required
        # ----------------------------------------------------------------------------
        "created_at" => { "type" => "string", "format" => "date-time" },
        "script_id" => { "type" => "string" },
        "state" => { "type" => "string", "enum" => STATES },
        "submit_status" => { "type" => "integer", "minimum" => 0, "maximum" => 255 },
        "submit_stdout" => { "type" => "string" },
        "submit_stderr" => { "type" => "string" },
        # ----------------------------------------------------------------------------
        # Psuedo - Required
        #
        # These should *probably* become required on the next major release of the metadata
        # ----------------------------------------------------------------------------
        "rendered_path" => { "type" => "string" },
        "version" => { "const": "1.alpha" },
        # ----------------------------------------------------------------------------
        # Optional
        # ----------------------------------------------------------------------------
        "end_time" => { "type" => ["string", "null"], "format" => "date-time" },
        "scheduler_id" => { "type" => ["string", "null"] },
        "scheduler_state" => { "type" => ["string", "null"] },
        "start_time" => { "type" => ["string", "null"], "format" => "date-time" },
        "estimated_start_time" => { "type" => ["string", "null"], "format" => "date-time" },
        "estimated_end_time" => { "type" => ["string", "null"], "format" => "date-time" },
        "stdout_path" => { "type" => ["string", "null"] },
        "stderr_path" => { "type" => ["string", "null"] },
        "results_dir" => { "type" => ["string", "null"] },
        "reason" => { "type" => ["string", "null"] },
      }
    })

    ACTIVE_SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["script_id", "created_at"],
      "properties" => {
        "script_id" => { "type" => "string" },
        "created_at" => { "type" => "string", "format" => "date-time" },
      }
    })

    def self.load_all
      Dir.glob(new(id: '*').metadata_path).map do |path|
        id = File.basename(File.dirname(path))
        job = new(id: id)
        if job.valid?(:load)
          job.tap(&:monitor)
        else
          FlightJob.logger.error("Failed to load missing/invalid job: #{id}")
          FlightJob.logger.info(job.errors.full_messages.join("\n"))
          nil
        end
      end.reject(&:nil?).sort
    end

    def self.transition_inactive
      Dir.glob(new(id: '*').initial_metadata_path).each do |path|
        new(id: File.basename(File.dirname(path))).transition_inactive
      end
    end

    def self.monitor_all
      # TODO: Do this on monitor
      transition_inactive

      Dir.glob(new(id: '*').active_index_path)
        .select { |p| File.exists?(p) }
        .map { |p| File.basename(File.dirname(p)) }
        .map { |id| new(id: id) }
        .map(&:monitor)
    end

    validate on: :load do
      unless submitted?
        errors.add(:submitted, 'the job has not been submitted')
      end

      unless (schema_errors = SCHEMA.validate(metadata).to_a).empty?
        FlightJob.logger.debug("The following metadata file is invalid: #{metadata_path}\n") do
          JSON.pretty_generate(schema_errors)
        end
        errors.add(:metadata, 'is invalid')
      end

      # Ensure the active file does not exist in terminal states
      # TODO: This will need to be reworked for array-jobs
      if STATES_LOOKUP[state] == :terminal
        FileUtils.rm_f active_index_path

      # Otherwise, ensure the active file does exist
      else
        FileUtils.touch active_index_path
      end
    end

    # TODO: Move onto transition helper
    attr_writer :id

    # Implicitly generates an ID by trying to create a randomised directory
    # This handles ID collisions if and when they occur
    def id
      @id ||= begin
        candidate = '-'
        while candidate[0] == '-' do
          # Generate a 8 byte base64 string that does not start with: '-'
          # NOTE: 6 bytes of randomness becomes 8 base64-chars
          candidate = SecureRandom.urlsafe_base64(6)
        end
        # Ensures the parent directory exists with mkdir -p
        FileUtils.mkdir_p FlightJob.config.jobs_dir
        # Attempt to create the directory with errors: mkdir
        FileUtils.mkdir File.join(FlightJob.config.jobs_dir, candidate)
        # Return the candidate
        candidate
      rescue Errno::EEXIST
        FlightJob.logger.debug "Retrying after job ID collision: #{candidate}"
        retry
      end
    end

    def script_id
      metadata['script_id']
    end

    def script_id=(input)
      metadata['script_id'] = input
    end

    def submitted?
      File.exists? metadata_path
    end

    def metadata_path
      @metadata_path ||= File.join(job_dir, 'metadata.yaml')
    end

    def active_index_path
      @active_index_path ||= File.join(job_dir, 'active.index')
    end

    # Stores the initial state of the metadata before the job is submitted
    #
    # A job does not truely exist until after it has been submitted, however this
    # causes jobs to be lost if the submission catastrophically fails. As a fallback,
    # The initial metadata is used to re-construct a failed job entry.
    def initial_metadata_path
      @initial_metadata_path ||= File.join(job_dir, 'metadata.initial.yaml')
    end

    def metadata
      @metadata ||= if File.exists? metadata_path
        YAML.load File.read(metadata_path)
      elsif File.exists? initial_metadata_path
        YAML.load File.read(initial_metadata_path)
      else
        { "version" => "1.alpha", "created_at" => DateTime.now.rfc3339 }
      end
    end

    # NOTE: This is a subset of the full metadata file which is stored in the active file
    # It stores rudimentary information about the job if the metadata file is never saved
    def active_metadata
      metadata.is_a?(Hash) ? metadata.slice('version', 'created_at', 'script_id') : {}
    end

    # Checks it the job has got stuck during the submission
    # This can happen if the job is interrupted during submission
    def transition_inactive
      # Remove the initial_metadata_path if metadata_path exists
      FileUtils.rm_f initial_metadata_path if File.exists? metadata_path
      return unless File.exists? initial_metadata_path

      schema_errors = ACTIVE_SCHEMA.validate(active_metadata).to_a
      if schema_errors.empty?
        # Check if the maximum pending submission time has elapsed
        start = DateTime.rfc3339(created_at).to_time.to_i
        now = Time.now.to_i
        if now - start > FlightJob.config.submission_period
          FlightJob.logger.error <<~ERROR
            The following job is being flaged as FAILED as it has not been submitted: #{id}
          ERROR
          metadata['state'] = 'FAILED'
          metadata['submit_status'] = 126
          metadata['submit_stdout'] = ''
          metadata['submit_stderr'] = 'Failed to run the submission command for an unknown reason'
          FileUtils.mkdir_p File.dirname(metadata_path)
          File.write metadata_path, YAML.dump(metadata)
          FileUtils.rm_f initial_metadata_path
        else
          FlightJob.logger.info "Ignoring the following job as it is pending submission: #{id}"
        end
      else
        FlightJob.logger.error <<~ERROR.chomp
          The following active file is invalid: #{initial_metadata_path}
        ERROR
        FileUtils.rm_f initial_metadata_path
      end
    end

    def load_script
      Script.new(id: script_id)
    end

    def created_at
      metadata['created_at']
    end

    def results_dir
      metadata['results_dir']
    end

    def state
      metadata['state']
    end

    def stdout_path
      metadata['stdout_path']
    end

    def stderr_path
      metadata['stderr_path']
    end

    def submitted?
      metadata['submit_status'] == 0
    end

    def scheduler_id
      metadata['scheduler_id']
    end

    def stdout_readable?
      return false unless stdout_path
      return false unless File.exists? stdout_path
      File.stat(stdout_path).readable?
    end

    def stderr_readable?
      return false if stderr_merged?
      return false unless stderr_path
      return false unless File.exists? stderr_path
      File.stat(stderr_path).readable?
    end

    def stderr_merged?
      stdout_path == stderr_path
    end

    def controls_file(name)
      controls_dir.file(name)
    end

    def submit
      JobTransitions::SubmitTransition.new(self).run!
    end

    def monitor
      JobTransitions::MonitorSingletonTransition.new(self).run!
    end

    def decorate
      Decorators::JobDecorator.new(self)
    end

    # Jobs need to be serialized via the decorator
    def serializable_hash
      raise InternalError, "Unexpectedly tried to serializer a job resource"
    end

    def controls_dir
      @controls_dir ||= ControlsDir.new(File.join(job_dir, 'controls'))
    end

    def job_dir
      @job_dir ||= File.join(FlightJob.config.jobs_dir, id)
    end

    def terminal?
      STATES_LOOKUP[state] == :terminal
    end

    protected

    def <=>(other)
      if created_at.nil? || other.created_at.nil?
        0 # This case SHOULD NOT be reached in practice, so further sorting isn't required
      else
        Time.parse(created_at) <=> Time.parse(other.created_at)
      end
    end
  end
end

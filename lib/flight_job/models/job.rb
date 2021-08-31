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

    # JSON:Schemer supports oneOf matcher, however this makes the kinda cryptic
    # error messages, super cryptic
    #
    # Instead there is an initial "default" validation, checks for the shared
    # required keys. Then the "job_type" is used to select the specific
    # validator.
    #
    # It is assumed the initial validator is ran before the others
    SHARED_KEYS = ["created_at", "job_type", "rendered_path", "script_id", "version"]
    SCHEMAS = {
      initial: JSONSchemer.schema({
        "type" => "object",
        "additionalProperties" => true,
        "required" => SHARED_KEYS,
        "properties" => {
          "created_at" => { "type" => "string", "format" => "date-time" },
          "job_type" => { "enum" => ["INITIALIZING", "SINGLETON", "FAILED_SUBMISSION"] },
          "rendered_path" => { "type" => "string", "minLength": 1 },
          "script_id" => { "type" => "string", "minLength": 1 },
          "version" => { "const" => "1.beta" }
        }
      }),

      "INITIALIZING" => JSONSchemer.schema({
        "type" => "object",
        "additionalProperties" => false,
        "required" => SHARED_KEYS,
        "properties" => {
          **SHARED_KEYS.map { |k| [k, {}] }.to_h,
          "job_type" => { "const" => "INITIALIZING" }
        }
      }),

      "FAILED_SUBMISSION" => JSONSchemer.schema({
        "type" => "object",
        "additionalProperties" => false,
        "required" => [*SHARED_KEYS, "submit_status", "submit_stdout", "submit_stderr"],
        "properties" => {
          **SHARED_KEYS.map { |k| [k, {}] }.to_h,
          "job_type" => { "const" => "FAILED_SUBMISSION" },
          # NOTE: There are two edge cases where submit_status is set to 126
          # * 'flight-job' fails to report back the status, OR
          # * 'submit.sh' lies about exiting 0
          #
          # If 'flight-job' never reports back the status, the job will eventually
          # be transitioned to FAILED_SUBMISSION/126.
          #
          # However the 'submit.sh' may exit 0 with invalid submit response JSON. This
          # is a *lie* and is also reported back as FAILED_SUBMISSION/126.
          "submit_status" => { "type" => "integer", "minimum" => 1, "maximum" => 255 },
          "submit_stdout" => { "type" => "string" },
          "submit_stderr" => { "type" => "string" },
        }
      }),

      "SINGLETON" => JSONSchemer.schema({
        "type" => "object",
        "additionalProperties" => false,
        "required" => [
          *SHARED_KEYS, 'submit_status', 'submit_stdout', 'submit_stderr',
          'scheduler_id', 'state', 'results_dir', 'stdout_path'
        ],
        "properties" => {
          # Required
          **SHARED_KEYS.map { |k| [k, {}] }.to_h,
          "job_type" => { "const" => "SINGLETON" },
          "submit_status" => { const: 0 },
          "submit_stdout" => { "type" => "string" },
          "submit_stderr" => { "type" => "string" },
          "state" => { "enum" => STATES },
          "scheduler_id" => { "type" => "string", "minLength" => 1 },
          "results_dir" => { "type" => "string", "minLength" => 1 },
          "stdout_path" => { "type" => "string", "minLength" => 1 },
          # Optional
          #
          # NOTE: The transient dependency between 'state' and times
          # are enforced by the monitor scripts.
          #
          # It is assumed they metadata will not be edited manually,
          # and thus will remain accurate.
          "estimated_start_time" => { "type" => ['date-time', 'null'] },
          "estimated_end_time" => { "type" => ['date-time', 'null'] },
          "start_time" => { "type" => ["date-time", "null"] },
          "end_time" => { "type" => ["date-time", "null"] },
          "reason" => { "type" => ["string", "null"] },
          # Optional - Non empty
          "scheduler_state" => { "type" => "string", "minLength" => 1 },
          "stderr_path" => { "type" => "string", "minLength" => 1 }
        }
      })
    }

    def self.load_all
      Dir.glob(new(id: '*').metadata_path).map do |path|
        id = File.basename(File.dirname(path))
        job = new(id: id)
        if job.valid?(:load)
          job.tap(&:monitor)
          if job.job_type == 'INITIALIZING'
            FlightJob.logger.debug("Skipping initializing job: #{job.id}")
            nil
          else
            job
          end
        else
          FlightJob.logger.error("Failed to load missing/invalid job: #{id}")
          FlightJob.logger.info(job.errors.full_messages.join("\n"))
          nil
        end
      end.reject(&:nil?).sort
    end

    def self.monitor_all
      Dir.glob(new(id: '*').active_index_path).each do |path|
        # Load the job
        id = File.basename(File.dirname(path))
        job = new(id: id)

        # Ensure it is valid
        unless job.valid?(:load)
          FlightJob.logger.error "Skipping monitor for invalid job: #{id}"
          FlightJob.logger.info(job.errors.full_messages.join("\n"))
          next
        end

        # Run the monitor
        job.monitor
      end
    end

    def self.submit(script)
      new(submit_script: script).tap(&:submit)
    end

    validate on: :load do
      # Ensure the active file does not exist in terminal states
      # TODO: This will need to be reworked for array-jobs
      if terminal?
        FileUtils.rm_f active_index_path

      # Otherwise, ensure the active file does exist
      else
        FileUtils.touch active_index_path
      end
    end

    # Verifies the metadata is valid before saving it
    validate on: [:load, :save_metadata] do
      # Run the initial schema, followed by the specific one
      schema_errors = SCHEMAS[:initial].validate(metadata).to_a
      if schema_errors.empty?
        schema_errors = SCHEMAS[metadata['job_type']].validate(metadata).to_a
      end

      # Add the schema errors if any
      unless schema_errors.empty?
        FlightJob.logger.debug("The following metadata file is invalid: #{metadata_path}\n") do
          JSON.pretty_generate(schema_errors)
        end
        errors.add(:metadata, 'is invalid')
      end
    end

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

    def submit_script=(script)
      # Initialize the job with the script
      if metadata.empty?
        metadata["created_at"] = Time.now.rfc3339
        metadata["job_type"] = "INITIALIZING"
        metadata["rendered_path"] = File.join(job_dir, script.script_name)
        metadata["script_id"] = script.id
        metadata["version"] = "1.beta"

      # Error has the job already exists
      else
        raise InternalError, "Cannot set the 'script' as the metadata is already loaded"
      end
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

    def metadata
      @metadata ||= if File.exists? metadata_path
        YAML.load File.read(metadata_path)
      else
        # NOTE: This is almost always an error condition, however it is up
        # to the validation to handle it. New jobs should use the submit
        # method
        {}
      end
    end

    # NOTE: This is a subset of the full metadata file which is stored in the active file
    # It stores rudimentary information about the job if the metadata file is never saved
    def active_metadata
      metadata.is_a?(Hash) ? metadata.slice('version', 'created_at', 'script_id') : {}
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
      case job_type
      when 'INITIALIZING'
        'PENDING'
      when 'FAILED_SUBMISSION'
        'FAILED'
      else
        metadata['state'] || 'UNKNOWN'
      end
    rescue
      # Various validations require the 'state', which depends on the
      # metadata being correct.
      #
      # This error can be ignored, as the metadata is validated independently
      Flight.logger.error "Failed to resolve the state for job '#{id}'"
      Flight.logger.debug $!
      return 'UNKNOWN'
    end

    def stdout_path
      metadata['stdout_path']
    end

    def stderr_path
      metadata['stderr_path']
    end

    def submitted?
      job_type != 'INITIALIZING'
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

    # Deliberately not a case statement to allow fall through
    def monitor
      if job_type == 'INITIALIZING'
        JobTransitions::FailedSubmissionTransition.new(self).run
      end
      if job_type == 'SINGLETON'
        JobTransitions::MonitorSingletonTransition.new(self).run!
      end
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

    def job_type
      metadata['job_type'] || raise(InternalError, <<~ERROR.chomp)
        Failed to resolve the 'job_type' for job '#{id}'
      ERROR
    end

    def save_metadata
      if valid?(:save_metadata)
        FileUtils.mkdir_p File.dirname(metadata_path)
        File.write metadata_path, YAML.dump(metadata)
      else
        FlightJob.logger.error("Failed to savve job metadata: #{id}")
        FlightJob.logger.info(errors.full_messages.join("\n"))
        raise InternalError, "Unexpectedly failed to save job '#{id}' metadata"
      end
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

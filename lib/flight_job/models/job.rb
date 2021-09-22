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

require_relative 'job/validator'

module FlightJob
  class Job < ApplicationModel
    RAW_SCHEMA = JSON.parse File.read(Flight.config.job_schema_path)
    SCHEMA_VERSION = RAW_SCHEMA['oneOf'][0]["properties"]['version']['const']

    PENDING_STATES = ['PENDING']
    TERMINAL_STATES = ['FAILED', 'COMPLETED', 'CANCELLED', 'UNKNOWN']
    RUNNING_STATES = ['RUNNING']
    NON_TERMINAL_STATES = [*PENDING_STATES, *RUNNING_STATES]
    STATES = [*NON_TERMINAL_STATES, *TERMINAL_STATES]

    STATES_LOOKUP = {}.merge(PENDING_STATES.map { |s| [s, :pending] }.to_h)
                      .merge(RUNNING_STATES.map { |s| [s, :running] }.to_h)
                      .merge(TERMINAL_STATES.map { |s| [s, :terminal] }.to_h)

    # Break up the raw schema into its components
    # This makes slightly nicer error reporting by removing the oneOf
    SCHEMAS = {
      common: JSONSchemer.schema(RAW_SCHEMA.dup.tap { |s| s.delete("oneOf") })
    }
    RAW_SCHEMA['oneOf'].each do |schema|
      type = schema['properties']['job_type']['const']
      SCHEMAS.merge!({ type => JSONSchemer.schema(schema) })
    end

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

    validates_with Job::Validator, on: :load,
      adjust_active_index: true,
      migrate_metadata: true
    validates_with Job::Validator, on: :save_metadata

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
        metadata["version"] = SCHEMA_VERSION

      # Error has the job already exists
      else
        raise InternalError, "Cannot set the 'script' as the metadata is already loaded"
      end
    end

    def submitted?
      File.exists? metadata_path
    end

    def failed_migration_path
      @failed_migration_path ||= File.join(
        job_dir, ".migration-failed.#{SCHEMA_VERSION}.0"
      )
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

    def reload_metadata
      @metadata = nil
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

    # DEPRECATED: This method belongs on the decorator!
    #
    # Unfortunately it is extensively used to control the life-cycle of a Job.
    # This makes fully removing it, tricky. Instead, calls to this method will be progressively
    # removed.
    def state
      Flight.logger.warn "DEPRECATED: Job#state does not function correctly for array tasks"
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
      stdout_path!
    rescue
      Flight.logger.debug $!
      nil
    end

    def stdout_path!
      case job_type
      when 'SINGLETON'
        metadata['stdout_path']
      else
        raise InvalidOperation, failure_message("Could not get the standard output")
      end
    end

    def stderr_path
      stderr_path!
    rescue
      Flight.logger.debug $!
      nil
    end

    def stderr_path!
      case job_type
      when 'SINGLETON'
        metadata['stderr_path']
      else
        raise InvalidOperation, failure_message("Could not get the standard error")
      end
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

    def monitor
      case job_type
      when 'INITIALIZING'
        JobTransitions::FailedSubmissionTransition.new(self).run
      when 'SINGLETON'
        JobTransitions::MonitorSingletonTransition.new(self).run!
      when 'ARRAY'
        JobTransitions::MonitorArrayTransition.new(self).run!
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

    # NOTE: Requires parity with task_dir
    def job_dir
      @job_dir ||= File.join(FlightJob.config.jobs_dir, id)
    end

    def terminal?
      case job_type
      when 'INITIALIZING'
        false
      when 'FAILED_SUBMISSION'
        true
      when 'SINGLETON'
        STATES_LOOKUP[metadata['state']] == :terminal
      when 'ARRAY'
        if metadata['lazy']
          false
        else
          !Task.load_last_non_terminal(id)
        end
      end
    end

    # NOTE: The job_type is used within the validation, thus the metadata
    # may not be hash
    def job_type
      hash = metadata.is_a?(Hash) ? metadata : {}
      hash['job_type']
    end

    def save_metadata
      if valid?(:save_metadata)
        FileUtils.mkdir_p File.dirname(metadata_path)
        File.write metadata_path, YAML.dump(metadata)
      else
        FlightJob.logger.error("Failed to save job metadata: #{id}")
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

    private

    # Generates an error message according to the job_type
    # The assumption being, the operation failed due to having the wrong type.
    def failure_message(desc)
      type = nil
      begin
        type = job_type
      rescue
        # NOOP - This method only generates messages, in practice this condition
        # should have already been caught
      end

      suffix =  case type
                when 'SINGLETON'
                  "for '#{id}' as it is an individual job."
                when 'ARRAY'
                  "for '#{id}' as it is an array job."
                when 'INITIALIZING'
                  "for job '#{id}' as it is pending submission."
                when 'FAILED_SUBMISSION'
                  "for job '#{id}' as it did not succesfully submit."
                else
                  "for job '#{id}' for an unknown reason."
                end
      "#{desc} #{suffix}"
    end
  end
end

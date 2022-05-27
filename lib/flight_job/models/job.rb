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

require_relative 'job/adjust_active_index'
require_relative 'job/merge_controls_with_metadata'
require_relative 'job/metadata'
require_relative 'job/broken_metadata'
require_relative 'job/migrate_metadata'
require_relative '../matcher'

module FlightJob
  class Job < ApplicationModel
    include Matcher

    PENDING_STATES = ['PENDING']
    TERMINAL_STATES = ['FAILED', 'COMPLETED', 'CANCELLED', 'UNKNOWN']
    RUNNING_STATES = ['RUNNING', 'COMPLETING']
    NON_TERMINAL_STATES = [*PENDING_STATES, *RUNNING_STATES]
    STATES = [*NON_TERMINAL_STATES, *TERMINAL_STATES]
    STATES_LOOKUP = {}.merge(PENDING_STATES.map { |s| [s, :pending] }.to_h)
                      .merge(RUNNING_STATES.map { |s| [s, :running] }.to_h)
                      .merge(TERMINAL_STATES.map { |s| [s, :terminal] }.to_h)

    def self.load_all(opts = nil)
      glob = File.join(Flight.config.jobs_dir, "*", "metadata.yaml")
      Dir.glob(glob).map do |path|
        id = File.basename(File.dirname(path))
        job = new(id: id)
        if job.pass_filter?(opts)
          if job.valid?
            job.tap(&:monitor)
          else
            Flight.logger.error("Invalid job: #{id}")
            Flight.logger.info(job.errors.full_messages.join("\n"))
            job
          end
        end
      end.reject(&:nil?).sort
    end

    def self.monitor_all
      glob = File.join(Flight.config.jobs_dir, "*", "active.index")
      Dir.glob(glob).each do |path|
        # Load the job
        id = File.basename(File.dirname(path))
        job = new(id: id)

        # Ensure it is valid
        unless job.valid?
          Flight.logger.error "Skipping monitor for invalid job: #{id}"
          Flight.logger.info(job.errors.full_messages.join("\n"))
          next
        end

        # Run the monitor
        job.monitor
      end
    end

    after_save AdjustActiveIndex
    after_initialize AdjustActiveIndex, if: :persisted?
    after_initialize MergeControlsWithMetadata, if: :persisted?
    after_initialize MigrateMetadata, if: :persisted?

    validate do
      unless metadata.valid?
        messages = metadata.errors.map { |e| e.message }
        errors.add(:metadata, messages.join("; "))
      end
    end

    delegate(*Metadata.attribute_names - %i[results_dir state stdout_path stderr_path], to: :metadata)
    delegate :persisted?, to: :metadata

    def save
      run_callbacks :save do
        metadata.save
      end
    end

    def pass_filter?(opts)
      return true unless opts && (opts.id || opts.script || opts.state)
      job_attributes.each_pair do |key, _|
        if opts[key]
          return false unless super(opts[key],params[key])
        end
      end
      true
    end

    def job_attributes
      @job_attributes ||= OpenStruct.new(id: id, script: script_id, state: self.decorate.state)
    end

    attr_writer :id
    def id
      return @id if @id
      raise InternalError, "Job#id was called before being set"
    end

    def failed_migration_path
      @failed_migration_path ||= File.join(
        job_dir, ".migration-failed.#{Metadata::SCHEMA_VERSION}.0"
      )
    end

    def metadata_path
      @metadata_path ||= File.join(job_dir, 'metadata.yaml')
    end

    def metadata
      @metadata ||= if File.exist?(metadata_path)
        Metadata.load_from_path(metadata_path, self)
      else
        # NOTE: This is almost always an error condition, however it is up
        # to the validation to handle it. New jobs should use the submit
        # method
        Flight.logger.warn("Setting metadata to empty hash for job #{id}; this probably isn't right")
        Metadata.blank(metadata_path, self)
      end
    end

    def initialize_metadata(script, answers)
      if persisted?
        raise InternalError, "Cannot initialize metadata for persisted job '#{id.to_s}'"
      else
        @metadata = Metadata.from_script(script, answers, self)
      end
    end

    def broken_metadata
      @broken_metadata ||= BrokenMetadata.new({ }, metadata_path, self)
    end

    def load_script
      Script.new(id: script_id)
    end

    # Return a job name that is independent from the scheduler.
    #
    # Ideally this will 1) be sensible; 2) be the same as the name used by the
    # scheduler; and 3) be consistent for identical submissions from the same
    # script.
    def name
      if submission_answers['job_name']
        submission_answers['job_name']
      elsif script = load_script
        script.answers['job_name'].presence || script.script_name
      else
        id
      end
    end

    def results_dir
      controls_file("results_dir").read || metadata.results_dir
    end

    # DEPRECATED: This method belongs on the decorator!
    #
    # Unfortunately it is extensively used to control the life-cycle of a Job.
    # This makes fully removing it, tricky. Instead, calls to this method will be progressively
    # removed.
    def state
      Flight.logger.warn "DEPRECATED: Job#state does not function correctly for array tasks"
      case job_type
      when 'SUBMITTING'
        'PENDING'
      when 'FAILED_SUBMISSION'
        'FAILED'
      else
        metadata.state || 'BROKEN'
      end
    rescue
      # Various validations require the 'state', which depends on the
      # metadata being correct.
      #
      # This error can be ignored, as the metadata is validated independently
      Flight.logger.error "Failed to resolve the state for job '#{id}'"
      Flight.logger.debug $!
      metadata.state || 'BROKEN'
    end

    def stdout_path
      case job_type
      when 'SINGLETON'
        metadata.stdout_path
      else
        raise InvalidOperation, failure_message("Could not get the standard output")
      end
    rescue
      Flight.logger.debug $!
      nil
    end

    def stderr_path
      case job_type
      when 'SINGLETON'
        metadata.stderr_path
      else
        raise InvalidOperation, failure_message("Could not get the standard error")
      end
    rescue
      Flight.logger.debug $!
      nil
    end

    def stdout_readable?
      return false unless stdout_path
      return false unless File.exist? stdout_path
      File.stat(stdout_path).readable?
    end

    def stderr_readable?
      return false if stderr_merged?
      return false unless stderr_path
      return false unless File.exist? stderr_path
      File.stat(stderr_path).readable?
    end

    def stderr_merged?
      stdout_path == stderr_path
    end

    def controls_file(name)
      controls_dir.file(name)
    end

    def desktop_id
      controls_file('flight_desktop_id').read
    end

    def desktop_id=(id)
      controls_file('flight_desktop_id').write(id)
    end

    def submit
      JobTransitions::Submitter.new(self).run!
    end

    def monitor
      metadata.with_save_point do
        success =
          case job_type
          when 'SUBMITTING'
            JobTransitions::FailedSubmitter.new(self).run
          when 'BOOTSTRAPPING'
            JobTransitions::BootstrapMonitor.new(self).run
          when 'SINGLETON'
            JobTransitions::SingletonMonitor.new(self).run
          when 'ARRAY'
            JobTransitions::ArrayMonitor.new(self).run
          when 'FAILED_SUBMISSION'
            # There is nothing to do in this case.  Return true to avoid logging a
            # confusing warning below.
            true
          end
        unless success
          Flight.logger.warn "Resetting metadata for job '#{id}'"
          metadata.restore_save_point
        end
        success
      end
    end

    def cancel
      JobTransitions::Canceller.new(self).run!
    end

    def decorate
      Decorators::JobDecorator.new(self)
    end

    # Jobs need to be serialized via the decorator
    def serializable_hash(opts = nil)
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
      when 'FAILED_SUBMISSION'
        true
      when 'SINGLETON'
        STATES_LOOKUP[metadata.state] == :terminal
      when 'ARRAY'
        if lazy
          false
        else
          !Task.load_last_non_terminal(id)
        end
      else
        false
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
                when 'SUBMITTING'
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

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
    STATE_MAP = YAML.load(File.read(FlightJob.config.state_map_path))
    TERMINAL_STATES = ['FAILED', 'COMPLETED', 'CANCELLED', 'UNKNOWN']
    RUNNING_STATES = ['RUNNING']
    RUNNING_OR_TERMINAL_STATES = [*RUNNING_STATES, *TERMINAL_STATES]
    STATES = ['PENDING', *RUNNING_STATES, *TERMINAL_STATES]

    SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["submit_status", "submit_stdout", "submit_stderr", "script_id", "created_at", "state"],
      "properties" => {
        "submit_status" => { "type" => "integer", "minimum" => 0, "maximum" => 255 },
        "submit_stdout" => { "type" => "string" },
        "submit_stderr" => { "type" => "string" },
        "script_id" => { "type" => "string" },
        "created_at" => { "type" => "string", "format" => "date-time" },
        "state" => { "type" => "string", "enum" => STATES },
        "scheduler_state" => { "type" => "string" },
        # NOTE: In practice this will normally be an integer, however this is not
        # guaranteed. As such it must be stored as a string.
        "scheduler_id" => { "type" => ["string", "null"] },
        "stdout_path" => { "type" => ["string", "null"] },
        "stderr_path" => { "type" => ["string", "null"] },
        "output_dir" => { "type" => ["string", "null"] },
        "reason" => { "type" => ["string", "null"] },
        "start_time" => { "type" => ["string", "null"], "format" => "date-time" },
        "end_time" => { "type" => ["string", "null"], "format" => "date-time" }
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

    SUBMIT_RESPONSE_SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["id", "stdout", "stderr", "output_dir"],
      "properties" => {
        "id" => { "type" => "string" },
        "stdout" => { "type" => "string" },
        "stderr" => { "type" => "string" },
        "output_dir" => { "type" => "string" }
      }
    })

    MONITOR_RESPONSE_SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["state"],
      "properties" => {
        "state" => { "type" => "string" },
        "reason" => { "type" => ["string", "null"] },
        "start_time" => { "type" => ["string", "null"] },
        "end_time" => { "type" => ["string", "null"] }
      }
    })

    def self.load_all
      Dir.glob(new(id: '*').metadata_path).map do |path|
        id = File.basename(File.dirname(path))
        job = new(id: id)
        if job.valid?(:load)
          job
        else
          FlightJob.logger.error("Failed to load missing/invalid script: #{id}")
          FlightJob.logger.debug(job.errors)
          nil
        end
      end.reject(&:nil?).sort
    end

    def self.load_active
      Dir.glob(new(id: '*').active_path).map do |path|
        new(id: File.basename(File.dirname(path)))
      end
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
    end

    validate on: :monitor do
      unless submitted?
        errors.add(:submitted, 'the job has not been submitted')
      end

      unless (schema_errors = SCHEMA.validate(metadata).to_a).empty?
        FlightJob.logger.debug("The following metadata file is invalid: #{metadata_path}\n") do
          JSON.pretty_generate(schema_errors)
        end
        errors.add(:metadata, 'is invalid')
      end

      unless scheduler_id
        errors.add(:scheduler_id, 'has not been set')
      end
    end

    validate on: :submit do
      if submitted?
        errors.add(:submitted, 'the job has already been submitted')
      end
      unless load_script.valid?(:load)
        errors.add(:script, 'is missing or invalid')
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

    def submitted?
      File.exists? metadata_path
    end

    def metadata_path
      @metadata_path ||= File.join(FlightJob.config.jobs_dir, id, 'metadata.yaml')
    end

    # This denotes a job that has been or will be given to the scheduler. The job is considered
    # "active" until it is in a terminal state.
    #
    # NOTE: Technically an "active" job may not exist. The existence criteria is determined by
    # the "metadata_path", which stores the result of the submission command. However a job
    # becomes active before it is submitted, hence it doesn't exist briefly.
    #
    # This allows jobs to be quasi-tracked even if a catastrophic failure occurs during the
    # submission that prevents the metadata file from being generated.
    def active_path
      @active_path ||= File.join(FlightJob.config.jobs_dir, id, 'active.yaml')
    end

    def metadata
      @metadata ||= if File.exists? metadata_path
        YAML.load File.read(metadata_path)
      elsif File.exists? active_path
        YAML.load File.read(active_path)
      else
        { "created_at" => DateTime.now.rfc3339 }
      end
    end

    # NOTE: This is a subset of the full metadata file which is stored in the active file
    # It stores rudimentary information about the job if the metadata file is never saved
    def active_metadata
      metadata.is_a?(Hash) ? metadata.slice('created_at', 'script_id') : {}
    end

    # Checks it the job has got stuck in an Active state and handles it accordingly
    # This can happen if the job is interrupted during submission
    def transition_inactive
      return unless File.exists? active_path
      schema_errors = ACTIVE_SCHEMA.validate(active_metadata).to_a

      if schema_errors.empty?
        # Check if the maximum pending submission time has elapsed
        start = DateTime.rfc3339(created_at).to_time.to_i
        now = Time.now.to_i
        if now - start > FlightJob.config.submission_period
          FlightJob.logger.error <<~ERROR
            The following job is being flaged as FAILED as it has not been submitted: #{id}
          ERROR
          self.state = 'FAILED'
          self.submit_status = 126
          self.submit_stdout = ''
          self.submit_stderr = 'Failed to run the submission command for an unknown reason'
          FileUtils.mkdir_p File.dirname(metadata_path)
          File.write metadata_path, YAML.dump(metadata)
          FileUtils.rm_f active_path
        else
          FlightJob.logger.info "Ignoring the following job as it is pending submission: #{id}"
        end
      else
        FlightJob.logger.error <<~ERROR.chomp
          The following active file is invalid: #{active_path}
        ERROR
        FileUtils.rm_f active_path
      end
    end

    def load_script
      Script.new(id: script_id)
    end

    def created_at
      metadata['created_at']
    end

    [
      "submit_status", "submit_stdout", "submit_stderr", "script_id", "state",
      "scheduler_id", "scheduler_state", "stdout_path", "stderr_path", "reason",
      "start_time", "end_time", "output_dir"
    ].each do |method|
      define_method(method) { metadata[method] }
      define_method("#{method}=") { |value| metadata[method] = value }
    end

    def serializable_hash
      { "id" => id }.merge(metadata)
    end

    # Takes the scheduler's state and converts it to an internal flight-job
    # one.
    # NOTE: The `state=` method should be used when updating the internal
    # state directly
    def update_scheduler_state(scheduler_state)
      self.state = STATE_MAP.fetch(scheduler_state, 'UNKNOWN')
      self.scheduler_state = scheduler_state
    end

    def submit
      unless valid?(:submit)
        FlightJob.config.logger("The script is not in a valid submission state: #{id}\n") do
          errors.full_messages
        end
        raise InternalError, 'Unexpectedly failed to submit the job'
      end
      script = load_script

      FlightJob.logger.info("Submitting Job: #{id}")
      cmd = [
        FlightJob.config.submit_script_path,
        script.script_path
      ]

      # Quasi-persist the job in the active "state"
      FileUtils.mkdir_p File.dirname(active_path)
      File.write active_path, YAML.dump(active_metadata)

      # Run the submission command
      execute_command(*cmd) do |status, out, err|
        # set the status/stdout/stderr
        self.submit_status = status.exitstatus
        self.submit_stdout = out
        self.submit_stderr = err

        # Set the initial state based on the exit status
        if submit_status == 0
          self.state = 'PENDING'
        else
          self.state = 'FAILED'
        end

        # Persist the current state of the job
        FileUtils.mkdir_p File.dirname(metadata_path)
        File.write metadata_path, YAML.dump(metadata)

        # Parse stdout on successful commands
        process_output('submit', status, out) do |data|
          self.scheduler_id = data['id']
          self.stdout_path = data['stdout']
          self.stderr_path = data['stderr']
          self.output_dir = data['output_dir']
        end

        # Persist the updated version of the metadata
        File.write(metadata_path, YAML.dump(metadata))
      end

      # TODO: Run the monitor

      # Remove the active file if the job is in a terminal state
      if TERMINAL_STATES.include?(state)
        FileUtils.rm_f active_path
      end
    end

    def monitor
      FlightJob.logger.info("Monitoring Job: #{id}")
      cmd = [FlightJob.config.monitor_script_path, scheduler_id]
      execute_command(*cmd) do |status, stdout, stderr|
        process_output('monitor', status, stdout) do |data|
          update_scheduler_state(data['state'])

          # The slurm monitor script will report the "expected start/end times"
          # as if they where the actual times. This means "start_time" should
          # only be updated when in a running or terminal state. Similarly, the
          # "end_time" should only be updated when in a terminal state.
          #
          # NOTE: This *might* give erroneous results if the job transitioned
          # from pending to terminal. In these cases, they would not have technically
          # started, but slurm may still set the "start_time"
          #
          # It is not possible to detect this condition at this point, as the monitor
          # runs infrequently. Thus a fast running job may "appear" to have skipped
          # the RUNNING_STATES.
          #
          # Consider refactoring
          if ['', nil].include?(data['start_time']) || !RUNNING_OR_TERMINAL_STATES.include?(state)
            self.start_time = nil
          else
            begin
              self.start_time = Time.parse(data['start_time']).to_datetime.rfc3339
            rescue ArgumentError
              FlightJob.logger.error "Failed to parse start_time: #{data['start_time']}"
              FlightJob.logger.debug $!.full_message
              raise_command_error
            end
          end

          if ['', nil].include?(data['end_time']) || !TERMINAL_STATES.include?(state)
            self.end_time = nil
          else
            begin
              self.end_time = Time.parse(data['end_time']).to_datetime.rfc3339
            rescue ArgumentError
              FlightJob.logger.error "Failed to parse end_time: #{data['end_time']}"
              FlightJob.logger.debug $!.full_message
              raise_command_error
            end
          end

          if data['reason'] == ''
            self.reason = nil
          elsif data['reason']
            self.reason = data['reason']
          end
          if valid?(:load)
            File.write(metadata_path, YAML.dump(metadata))
          end
        end
      end

      # Only preform the active_path removal if the command exists
      # successfully
      if TERMINAL_STATES.include?(self.state)
        FileUtils.rm_f active_path
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

    def process_output(type, status, out)
      schema = case type
               when 'submit'
                 SUBMIT_RESPONSE_SCHEMA
               when 'monitor'
                 MONITOR_RESPONSE_SCHEMA
               else
                 raise InternalError, "Unknown command type: #{type}"
               end

      if status.success?
        string = out.split("\n").last
        begin
          data = JSON.parse(string)
          errors = schema.validate(data).to_a
          if errors.empty?
            yield(data) if block_given?
          else
            FlightJob.logger.error("Invalid #{type} response for job: #{id}")
            FlightJob.logger.debug(JSON.pretty_generate(errors))
            raise_command_error
          end
        rescue JSON::ParserError
          FlightJob.logger.error("Failed to parse #{type} JSON for job: #{id}")
          FlightJob.logger.debug($!.message)
          raise_command_error
        end
      else
        # NOTE: Commands are allowed to fail at this point. The caller is
        # responsible for generating an appropriate message
        FlightJob.logger.error("Failed to #{type} job: #{id}")
      end
    end

    def execute_command(*cmd)
      # NOTE: Should the PATH be configurable instead of inherited from the environment?
      # This could lead to differences when executed via the CLI or the webapp
      env = ENV.slice('PATH', 'HOME', 'USER', 'LOGNAME')
      cmd_stdout, cmd_stderr, status = Open3.capture3(env, *cmd, unsetenv_others: true, close_others: true)

      FlightJob.logger.debug <<~DEBUG
        COMMAND: #{cmd.join(" ")}
        STATUS: #{status.exitstatus}
        STDOUT:
        #{cmd_stdout}
        STDERR:
        #{cmd_stderr}
      DEBUG

      yield(status, cmd_stdout, cmd_stderr)
    end

    def raise_command_error
      raise CommandError, <<~ERROR.chomp
        An error occurred when integrating with the external scheduler service!
        Please contact your system administrator for further assistance.
      ERROR
    end
  end
end

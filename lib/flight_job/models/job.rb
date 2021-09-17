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
    PENDING_STATES = ['PENDING']
    TERMINAL_STATES = ['FAILED', 'COMPLETED', 'CANCELLED', 'UNKNOWN']
    RUNNING_STATES = ['RUNNING']
    STATES = [*PENDING_STATES, *RUNNING_STATES, *TERMINAL_STATES]

    STATES_LOOKUP = {}.merge(PENDING_STATES.map { |s| [s, :pending] }.to_h)
                      .merge(RUNNING_STATES.map { |s| [s, :running] }.to_h)
                      .merge(TERMINAL_STATES.map { |s| [s, :terminal] }.to_h)

    SCHEMA = JSONSchemer.schema({
      "$comment" => "strip-schema",
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
        "version" => { "const": 0 },
        # ----------------------------------------------------------------------------
        # Optional
        # ----------------------------------------------------------------------------
        "end_time" => { "type" => ["string", "null"], "format" => "date-time" },
        "scheduler_id" => { "type" => ["string", "null"] },
        "scheduler_state" => { "type" => "string" },
        "start_time" => { "type" => ["string", "null"], "format" => "date-time" },
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

    SUBMIT_RESPONSE_SCHEMA = JSONSchemer.schema({
      "$comment" => "strip-schema",
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["id", "results_dir"],
      "properties" => {
        "id" => { "type" => "string" },
        "stdout" => { "type" => ["string", "null"] },
        "stderr" => { "type" => ["string", "null"] },
        "results_dir" => { "type" => "string" },
      }
    })

    MONITOR_RESPONSE_SCHEMA = JSONSchemer.schema({
      "$comment" => "strip-schema",
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["state"],
      "properties" => {
        "state" => { "type" => "string" },
        "reason" => { "type" => ["string", "null"] },
        "start_time" => { "type" => ["string", "null"] },
        "end_time" => { "type" => ["string", "null"] },
        "estimated_start_time" => { "type" => ["string", "null"] },
        "estimated_end_time" => { "type" => ["string", "null"] }
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

    validate on: :load do
      unless submitted?
        errors.add(:submitted, 'the job has not been submitted')
      end

      unless (schema_errors = SCHEMA.validate(metadata).to_a).empty?
        Flight.logger.info "Job '#{id.to_s}' metadata is invalid"
        LogJSONSchemaErrors.new(schema_errors, :info).log
        errors.add(:metadata, 'is invalid')
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
      @metadata_path ||= File.join(job_dir, 'metadata.yaml')
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
        { "version" => 0, "created_at" => DateTime.now.rfc3339 }
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
          self.state = 'FAILED'
          self.submit_status = 126
          self.submit_stdout = ''
          self.submit_stderr = 'Failed to run the submission command for an unknown reason'
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

    def actual_start_time
      return nil if STATES_LOOKUP[state] == :pending
      start_time
    end

    def estimated_start_time
      return nil unless STATES_LOOKUP[state] == :pending
      start_time
    end

    def actual_end_time
      return nil unless STATES_LOOKUP[state] == :terminal
      end_time
    end

    def estimated_end_time
      return nil if STATES_LOOKUP[state] == :terminal
      end_time
    end

    [
      "submit_status", "submit_stdout", "submit_stderr", "script_id", "state",
      "scheduler_id", "scheduler_state", "stdout_path", "stderr_path", "reason",
      "start_time", "end_time", "results_dir"
    ].each do |method|
      define_method(method) { metadata[method] }
      define_method("#{method}=") { |value| metadata[method] = value }
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

    def serializable_hash(opts = nil)
      opts ||= {}
      {
        "id" => id,
        "actual_start_time" => actual_start_time,
        "estimated_start_time" => estimated_start_time,
        "actual_end_time" => actual_end_time,
        "estimated_end_time" => estimated_end_time,
        "controls" => controls_dir.serializable_hash,
      }.merge(metadata).tap do |hash|
        # NOTE: The API uses the 'size' attributes as a proxy check to exists/readability
        #       as well as getting the size. Non-readable stdout/stderr would be
        #       unusual, and can be ignored
        hash["stdout_size"] = File.size(stdout_path) if stdout_readable?
        hash["stderr_size"] = File.size(stderr_path) if stderr_readable?

        if Flight.config.includes.include? 'script'
          hash['script'] = load_script
        end

        # Always serialize the result_files
        if results_dir && Dir.exist?(results_dir)
          files =  Dir.glob(File.join(results_dir, '**/*'))
                      .map { |p| Pathname.new(p) }
                      .reject(&:directory?)
                      .select(&:readable?) # These would be unusual and should be rejected
                      .map { |p| { file: p.to_s, size: p.size } }
          hash['result_files'] = files
        else
          hash['result_files'] = nil
        end
      end
    end

    def controls_file(name)
      controls_dir.file(name)
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
      # Validate and load the script
      unless valid?(:submit)
        FlightJob.config.logger("The script is not in a valid submission state: #{id}\n") do
          errors.full_messages
        end
        raise InternalError, 'Unexpectedly failed to submit the job'
      end
      script = load_script

      # Generate the initial metadata path file
      FileUtils.mkdir_p File.dirname(initial_metadata_path)
      File.write initial_metadata_path, YAML.dump(active_metadata)

      # Duplicate the script into the job's directory
      # NOTE: Eventually this should probably be named after the job_name question
      metadata["rendered_path"] = File.join(job_dir, script.script_name)
      FileUtils.cp script.script_path, metadata["rendered_path"]

      # Run the submission command
      FlightJob.logger.info("Submitting Job: #{id}")
      cmd = [FlightJob.config.submit_script_path, metadata["rendered_path"]]
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
          self.stdout_path = data['stdout'].blank? ? nil : data['stdout']
          self.stderr_path = data['stderr'].blank? ? nil : data['stderr']
          self.results_dir = data['results_dir']
        end

        # Persist the updated version of the metadata
        File.write(metadata_path, YAML.dump(metadata))
      end
    end

    def monitor
      # Skip jobs that have terminated, this allows the method to be called liberally
      if STATES_LOOKUP[state] == :terminal
        FlightJob.logger.debug "Skipping monitor for terminated job: #{id}"
        return
      end

      # Jobs without a scheduler ID should not be in a running/pending state. It is
      # an error condition if they are
      unless scheduler_id
        FlightJob.logger.error "Can not monitor job '#{id}' as it did not report its scheduler_id"
        self.reason = "Did not report it's scheduler ID"
        self.state = "FAILED"
        File.write(metadata_path, YAML.dump(metadata))
        return
      end

      FlightJob.logger.info("Monitoring Job: #{id}")
      cmd = [FlightJob.config.monitor_script_path, scheduler_id]
      execute_command(*cmd) do |status, stdout, stderr|
        process_output('monitor', status, stdout) do |data|
          update_scheduler_state(data['state'])

          process_times data['estimated_start_time'],
                        data['start_time'],
                        data['estimated_end_time'],
                        data['end_time']

          if data['reason'] == ''
            self.reason = nil
          elsif data['reason']
            self.reason = data['reason']
          end
          File.write(metadata_path, YAML.dump(metadata))
        end
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

    def controls_dir
      @controls_dir ||= ControlsDir.new(File.join(job_dir, 'controls'))
    end

    def job_dir
      @job_dir ||= File.join(FlightJob.config.jobs_dir, id)
    end

    def process_times(est_start, start, est_end, end_time)
      # The monitor script does not always distinguish between actual/estimated
      # start/end times. Doing so reliable would require knowledge of the state
      # mapping file as 'scontrol' does not make a distinction.
      #
      # Instead the estimated/actual times are inferred by the state. To prevent
      # transient dependencies between attributes, their is only one version of
      # the `start_time`/`end_time` fields are stored each. The state is then
      # used to infer which is correct.

      case state
      when *PENDING_STATES
        self.start_time = parse_time(est_start, type: "estimated_start_time")
        self.end_time = parse_time(est_end, type: "estimated_end_time")
      when *RUNNING_STATES
        self.start_time = parse_time(start, type: "actual_start_time")
        self.end_time = parse_time(est_end, type: "estimated_end_time")
      else
        self.start_time = parse_time(start, type: "actual_start_time")
        self.end_time = parse_time(end_time, type: "actual_end_time")
      end
    end

    def parse_time(time, type:)
      return nil if ['', nil].include?(time)
      Time.parse(time).strftime("%Y-%m-%dT%T%:z")
    rescue ArgumentError
      FlightJob.logger.error "Failed to parse #{type}: #{time}"
      FlightJob.logger.debug $!.full_message
      raise_command_error
    end

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
            LogJSONSchemaErrors.new(errors, :warn).log
            raise_command_error
          end
        rescue JSON::ParserError
          FlightJob.logger.error("Failed to parse #{type} JSON for job: #{id}")
          FlightJob.logger.warn(string)
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
      env = ENV.slice('PATH', 'HOME', 'USER', 'LOGNAME').tap do |h|
        h['CONTROLS_DIR'] = controls_dir.path
      end
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

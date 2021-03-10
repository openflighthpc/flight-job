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
    TERMINAL_STATES = ['FAILED', 'COMPLETED', 'CANCELLED', 'UNKNOWN']
    STATES = ['PENDING', 'RUNNING', *TERMINAL_STATES]

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
        # NOTE: In practice this will normally be an integer, however this is not
        # guaranteed. As such it must be stored as a string.
        "scheduler_id" => { "type" => "string" },
        "stdout_path" => { "type" => "string" },
        "stderr_path" => { "type" => "string" },
        "reason" => { "type" => "string" },
        "start_time" => { "type" => "string", "format" => "date-time" },
        "end_time" => { "type" => "string", "format" => "date-time" }
      }
    })

    SUBMIT_RESPONSE_SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["id", "stdout", "stderr"],
      "properties" => {
        "id" => { "type" => "string" },
        "stdout" => { "type" => "string" },
        "stderr" => { "type" => "string" }
      }
    })

    MONITOR_RESPONSE_SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["state"],
      "properties" => {
        "state" => { "type" => "string" },
        "reason" => { "type" => ["string", "null"] },
        "start_time" => { "type" => ["string", "null"], "format" => "date-time" },
        "end_time" => { "type" => ["string", "null"], "format" => "date-time" }
      }
    })

    # def self.from_metadata_path(path)
    #   unless File.exists? path
    #     FlightJobScriptAPI.logger.error "Failed to locate job metadata path: #{path}"
    #     return nil
    #   end
    #   match = match_regex.match(path)

    #   if match.nil?
    #     FlightJobScriptAPI.logger.error "Failed to parse job metadata path: #{path}"
    #     return nil
    #   end

    #   data = (YAML.load(File.read(path)) || {}).slice(*METADATA_KEYS)
    #   job = new(
    #     user: match['user'],
    #     id: match['id'],
    #     **data.map { |k, v| [k.to_sym, v] }.to_h
    #   )

    #   # Ensure the job is valid
    #   if job.valid?
    #     job
    #   else
    #     FlightJobScriptAPI.logger.error "A validation error occurred when loading job: #{path}"
    #     FlightJobScriptAPI.logger.debug(job.full_messages)
    #     return nil
    #   end
    # end

    validate on: :load do
      unless submitted?
        errors.add(:submitted, 'the job has not been submitted')
      end

      unless (errors = SCHEMA.validate(metadata).to_a).empty?
        FlightJob.logger.debug("The following metadata file is invalid: #{metadata_path}\n") do
          JSON.pretty_generate(errors)
        end
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

    def id
      @id ||= SecureRandom.uuid
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
      @active_path ||= File.join(FlightJob.config.jobs_dir, id, 'active')
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
      metadata.slice('created_at', 'script_id')
    end

    def load_script
      Script.new(id: script_id)
    end

    def created_at
      metadata['created_at']
    end

    [
      "submit_status", "submit_stdout", "submit_stderr", "script_id", "state", "scheduler_id",
      "stdout_path", "stderr_path", "reason", "start_time", "end_time"
    ].each do |method|
      define_method(method) { metadata[method] }
      define_method("#{method}=") { |value| metadata[method] = value }
    end

    def serializable_hash
      { "id" => id }.merge(metadata)
    end

    def submit
      unless valid?(:submit)
        FlightJob.config.logger("The script is not in a valid submission state: #{id}\n") do
          errors.full_messages
        end
        raise InternalError, 'Unexpectedly failed to submit the job'
      end

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
          self.status = 'PENDING'
        else
          self.status = 'FAILED'
        end

        # Persist the current state of the job
        FileUtils.mkdir_p File.dirname(metadata_path)
        File.write metadata_path, YAML.dump(metadata)

        # Parse stdout on successful commands
        process_output('submit', status, out) do |data|
          self.scheduler_id = data['id']
          self.stdout_path = data['stdout']
          self.stderr_path = data['stderr']
        end

        # Persist the updated version of the metadata
        File.write(metadata_path, YAML.dump(to_h))
      end

      # TODO: Run the monitor

      # Remove the active file if the job is in a terminal state
      if TERMINAL_STATES.include?(state)
        FileUtils.rm_f active_path
      end
    end

    def monitor
      FlightJobScriptAPI.logger.info("Monitoring Job: #{id}")
      cmd = [FlightJob.config.monitor_script_path, scheduler_id]
      execute_command(*cmd) do |status, stdout, stderr|
        process_output('monitor', status, stdout) do |data|
          self.state = data['state']
          self.start_time = data['start_time'] if data['start_time']
          self.end_time = data['end_time'] if data['end_time']
          if data['reason'] == ''
            self.reason = nil
          elsif data['reason']
            self.reason = data['reason']
          end
          File.write(metadata_path, YAML.dump(metadata))
        end
      end
    ensure
      active_path = self.class.active_path(user, id)
      if TERMINAL_STATES.include?(self.state)
        FileUtils.rm_f active_path
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

      FlightJobScriptAPI.logger.debug <<~DEBUG
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

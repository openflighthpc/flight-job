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

module FlightJob
  module JobTransitions
    module JobTransitionHelper
      def execute_command(*cmd, tag:)
        # NOTE: Should the PATH be configurable instead of inherited from the environment?
        # This could lead to differences when executed via the CLI or the webapp
        env = ENV.slice('PATH', 'HOME', 'USER', 'LOGNAME').tap do |h|
          h['CONTROLS_DIR'] = controls_dir.path
        end
        cmd_stdout, cmd_stderr, status = Open3.capture3(env, *cmd, unsetenv_others: true, close_others: true)

        unless status.success?
          FlightJob.logger.error("Failed to #{tag} job: #{id}")
        end

        FlightJob.logger.debug <<~DEBUG
          COMMAND: #{cmd.join(" ")}
          STATUS: #{status.exitstatus}
          STDOUT:
          #{cmd_stdout}
          STDERR:
          #{cmd_stderr}
        DEBUG

        data = nil
        if status.success?
          begin
            data = JSON.parse(cmd_stdout.split("\n").last.to_s)
          rescue JSON::ParserError
            FlightJob.logger.error("Failed to parse #{tag} JSON for job: #{id}")
            FlightJob.logger.debug($!.message)
            raise_command_error
          end
        end

        yield(status, cmd_stdout, cmd_stderr, data)
      end

      def raise_command_error
        raise CommandError, <<~ERROR.chomp
          An error occurred when integrating with the external scheduler service!
          Please contact your system administrator for further assistance.
        ERROR
      end

      def validate_data(schema, data, tag:)
        errors = schema.validate(data).to_a
        unless errors.empty?
          FlightJob.logger.error("Invalid #{tag} response for job: #{id}")
          FlightJob.logger.debug(JSON.pretty_generate(errors))
          raise_command_error
        end
      end

      def apply_task_attributes(object, opts)
        # Apply the generic keys to the metadata
        opts.slice("state", "reason")
            .each { |k, v| object.metadata[k] = (v == "" ? nil : v) }

        # Apply the scheduler_state, defaulting to UNKNOWN when appropriate
        if object.metadata['state'] == 'UNKNOWN' && [nil, ''].include?(opts['scheduler_state'])
          object.metadata['scheduler_state'] = 'unknown'
        else
          object.metadata['scheduler_state'] = opts['scheduler_state']
        end

        # Parse and apply the time based keys
        opts.slice("start_time", "end_time", "estimated_start_time", "estimated_end_time")
            .each { |k, t| object.metadata[k] = parse_time(t, type: k, object: object) }

        # Conditionally apply path keys
        opts.slice("stdout_path", "stderr_path")
            .each do |key, path|
          # The scheduler *may* loose track of the paths eventually, this is to be
          # expected and can be safely ignored
          next if [nil, ""].include? path

          # Set the path
          if object.metadata[key].nil?
            object.metadata[key] = path

          # This shouldn't happen in practice. This scheduler is assumable doing
          # something odd? Log the error and continue.
          elsif object.metadata[key] != path
            FlightJob.logger.error <<~ERROR.chomp
              Attempted to modify the #{key} for #{object_tag(object)}
              Original: #{object.metadata[key]}
              Provided: #{path}

              The provided value has been discared!
            ERROR
          end
        end
      end

      def parse_time(time, object:, type:)
        return nil if ['', nil].include?(time)
        Time.parse(time).strftime("%Y-%m-%dT%T%:z")
      rescue ArgumentError
        FlightJob.logger.error "Failed to parse #{object_tag(object)} #{type}: #{time}"
        FlightJob.logger.debug $!.full_message
        return nil
      end

      def object_tag(object)
        case object
        when Job
          "job '#{object.id}'"
        when Task
          "task #{object.tag}"
        else
          "unknown"
        end
      end
    end
  end
end
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
    end
  end
end

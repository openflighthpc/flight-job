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
    class CancelTransition
      def initialize(job)
        @job = job
      end

      def run
        if @job.terminal?
          # In practice, this condition shouldn't be reached. However preventing it
          # is up to the CLI's implementation
          FlightJob.logger.info "Cancelling Terminated Job: #{@job.id}"
        else
          FlightJob.logger.info "Cancelling Job: #{@job.id}"
        end

        cmd = [Flight.config.cancel_script_path, @job.scheduler_id]
        execute_command(*cmd, tag: 'cancel') do |status, _o, _e|
          # Run the monitor when:
          # * Cancel runs successful, or
          # * If the job is non-terminal (it may have changed)
          @job.monitor if status.success? || @job.terminal?
          if status.success?
            true
          elsif @job.terminal?
            false
          else
            raise CommandError, <<~ERROR.chomp
            Unexpectedly failed to cancel job '#{@job.id}'!
            Please contact your system administrator for futher assistance.
            ERROR
          end
        end
      end

      private

      def execute_command(*cmd, tag:)
        env = ENV.slice('PATH', 'HOME', 'USER', 'LOGNAME')
        cmd_stdout, cmd_stderr, status = Open3.capture3(env, *cmd, unsetenv_others: true, close_others: true)

        unless status.success?
          FlightJob.logger.error("Failed to #{tag} job: #{@job.id}")
        end

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
    end
  end
end

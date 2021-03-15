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

require 'open3'

module FlightJob
  module Commands
    class SubmitJob < Command
      def run
        check_cron
        job = Job.new(script_id: script.id)
        job.submit
        puts Outputs::InfoJob.build_output(submit: true, **output_options).render(job)
      end

      def script
        @script ||= load_script(args.first)
      end

      def check_cron
        env = ENV.slice('PATH', 'HOME', 'USER', 'LOGNAME')
        out, err, status = Open3.capture3(env, FlightJob.config.check_cron, unsetenv_others: true, close_others: true)
        FlightJob.logger.debug <<~DEBUG
          Result from cron-check
          STATUS: #{status.exitstatus}
          STDOUT:
          #{out}
          STDERR:
          #{err}
        DEBUG
        unless status.exitstatus == 0
          raise InternalError, <<~ERROR.chomp
            Failed to install the job monitor!
            Please contact your system administrator for further assistance.
          ERROR
        end
      end
    end
  end
end

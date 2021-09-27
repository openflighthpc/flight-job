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
    class ListJobResults < Command
      # The 'ls' command will fail if bad arguments are provided to it. This can
      # not be easily detected as 'ls' will likely exit 2 regardless. Instead a
      # generic error is raised instead.
      LS_ERROR = "An error occurred when running the 'ls' command!"

      def run
        job = load_job(args.first)
        assert_results_dir_exists(job, allow_empty: advanced?)

        FlightJob.logger.debug "Running: ls #{job.results_dir} #{ls_options.join(" ")}"
        cmd = ['ls', job.results_dir, *ls_options]

        status = if advanced?
          # When the user has provided options to the `ls` command, emit
          # STDOUT/STDERR directly to the terminal
          Kernel.system(*cmd)
        else
          # When we control the `ls` options we provide nicer error messages.
          stdout, status = Open3.capture2(*cmd)
          puts stdout if status.success?
          status.success?
        end

        # Handle errors
        raise InternalError, LS_ERROR unless status
      end

      private

      # Return true if the user has provided options to `ls`.
      def advanced?
        args.length > 1
      end

      def ls_options
        @ls_options ||= begin
          base = []
          base << '-lAR' if opts.verbose
          base << '--color' if $stdout.tty?
          [*base, *args[1..]]
        end
      end
    end
  end
end

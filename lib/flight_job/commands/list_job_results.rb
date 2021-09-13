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
      HARD_ERROR = "An error occurred when running the 'ls' command!"

      def run
        job = load_job(args.first)
        assert_results_dir_exists(job)
        FlightJob.logger.debug "Running: ls #{job.results_dir} #{ls_options.join(" ")}"
        cmd = ['ls', job.results_dir, *ls_options]

        status = if hard_wrap?
          # When hard wrapping, emit STDOUT/STDERR directly to the terminal
          Kernel.system(*cmd)
        else
          # When soft wrapping, hide the ls error
          stdout, status = Open3.capture2(*cmd)
          if status.success? && stdout.empty?
            if Job::TERMINAL_STATES.include?(job.state)
              $stderr.puts pastel.yellow 'No job results found.'
            else
              $stderr.puts pastel.yellow 'No job results found, please try again latter...'
            end
          elsif status.success?
            puts stdout
          end
          status.success?
        end

        # Handle errors
        raise InternalError, HARD_ERROR unless status
      end

      private

      def hard_wrap?
        args.length > 1
      end

      def ls_options
        @ls_options ||= begin
          base = []
          base << '-laR' if opts.verbose
          base << '--color' if $stdout.tty?
          [*base, *args[1..]]
        end
      end
    end
  end
end

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
  module Commands
    class ListJobResults < Command
      def run
        @job = load_job(args.first)
        assert_output_dir_exists
        FlightJob.logger.debug "Running: ls #{@job.output_dir} #{ls_options.join(" ")}"
        Kernel.system('ls', @job.output_dir, *ls_options)
      end

      private

      def assert_output_dir_exists
        # NOTE: Jobs created with old versions of flight-job will not have an
        # output directory.
        unless @job.output_dir
          raise MissingError, "The job did not report its output directory"
        end
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

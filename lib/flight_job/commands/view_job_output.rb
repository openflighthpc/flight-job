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
    class ViewJobOutput < Command
      def run
        assert_command_type_valid
        assert_file_path
        pager.page(File.read(file_path))
      end

      private

      def assert_command_type_valid
        return if [:stdout, :stderr].include?(opts.type)
        raise InternalError, "Invalid output type #{opts.type.inspect}"
      end

      def assert_file_path
        if opts.type == :stderr && job.stderr_merged?
          prog_name = ENV.fetch('FLIGHT_PROGRAM_NAME') { 'bin/job' }
          raise MissingError, <<~ERROR.chomp
            Cannot display the job's standard error as it has been merged with standard out.
            Please run the following instead:
            #{pastel.yellow "#{prog_name} view-job-stdout #{job.id}"}
          ERROR
        end

        unless File.exists?(file_path)
          raise MissingError, "The job's standard " \
            "#{opts.type == :stdout ? 'output' : 'error'} file does not exists: "\
            "#{pastel.yellow(file_path)}"
        end
      end

      def file_path
        if opts.type == :stdout
          job.stdout_path
        else
          job.stderr_path
        end
      end

      def job
        @job ||= load_job(args.first)
      end
    end
  end
end

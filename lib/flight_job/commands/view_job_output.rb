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
        @job = load_job(args.first)
        assert_job_submitted
        assert_type_valid
        assert_stderr_not_merged if opts.type == :stderr
        file_path = @job.send("#{opts.type}_path")
        assert_file_exists(file_path)
        pager.page(File.read(file_path))
      end

      private

      def assert_job_submitted
        return if @job.submit_status == 0
        raise MissingError, "The job's standard " \
          "#{opts.type == :stdout ? 'output' : 'error'} is not available as "\
          "the job did not succesfully submit"
      end

      def assert_type_valid
        return if [:stdout, :stderr].include?(opts.type)
        raise InternalError, "Invalid output type #{opts.type.inspect}" 
      end

      def assert_stderr_not_merged
        if @job.stderr_merged?
          prog_name = ENV.fetch('FLIGHT_PROGRAM_NAME') { 'bin/job' }
          raise MissingError, <<~ERROR.chomp
            Cannot display the job's standard error as it has been merged with standard out.
            Please run the following instead:
            #{pastel.yellow "#{prog_name} view-job-stdout #{@job.id}"}
          ERROR
        end
      end

      def assert_file_exists(path)
        unless File.exists?(path)
          raise MissingError, "The job's standard " \
            "#{opts.type == :stdout ? 'output' : 'error'} file does not exists: "\
            "#{pastel.yellow(path)}"
        end
      end
    end
  end
end

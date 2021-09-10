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
        assert_output_type_valid
        assert_stderr_not_merged if viewing_stderr?
        unless page_file(file_path)
          raise_file_missing(file_path)
        end
      end

      private

      def assert_output_type_valid
        return if [:job_stdout, :job_stderr, :task_stdout, :task_stderr].include?(opts.type)
        raise InternalError, "Invalid output type #{opts.type.inspect}"
      end

      def assert_stderr_not_merged
        if stderr_merged?
          prog_name = ENV.fetch('FLIGHT_PROGRAM_NAME') { 'bin/job' }
          cmd = viewing_job? ? 'view-job-stdout' : 'view-array-task-stdout'
          object_name = viewing_job? ? 'job' : 'task'
          raise MissingError, <<~ERROR.chomp
            Cannot display the #{object_name}'s standard error as it has been merged with standard out.
            Please run the following instead:
            #{pastel.yellow "#{prog_name} #{cmd} #{args.join(" ")}"}
          ERROR
        end
      end

      def raise_file_missing(path)
        output_type = viewing_stderr? ? 'error' : 'output'
        object_name = viewing_job? ? 'job' : 'task'
        raise MissingError, "The #{object_name}'s standard " \
          "#{output_type} file does not exists: "\
          "#{pastel.yellow(path)}"
      end

      def file_path
        if viewing_stderr?
          object.metadata['stderr_path']
        else
          object.metadata['stdout_path']
        end
      end

      def object
        @object ||= if viewing_job?
          load_job(*args)
        else
          Task.load(*args)
        end
      end

      def viewing_stderr?
        [:job_stderr, :task_stderr].include?(opts.type)
      end

      def viewing_job?
        [:job_stdout, :job_stderr].include?(opts.type)
      end

      def stderr_merged?
        object.metadata.slice('stdout_path', 'stderr_path').values.uniq.length == 1
      end
    end
  end
end

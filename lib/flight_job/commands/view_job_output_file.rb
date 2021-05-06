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
    class ViewJobOutputFile < Command
      def run
        # Ensure the job can be found
        job

        # Determine the file path
        path = file_path
        raise MissingError, <<~ERROR.chomp unless File.exists?(path)
          The selected file does not exists: #{pastel.yellow path}
        ERROR

        # Display the file
        pager.page File.read(path)
      end

      def file_path
        sources = []
        sources << :stdout if opts.stdout
        sources << :stderr if opts.stderr
        sources << :input if args.length > 1

        # TODO: This may need to be removed if the combined command isn't used
        if sources.empty?
          raise InputError, <<~ERROR.chomp
            Please provide the file you wish to open!
            #{pastel.yellow "#{CLI.program(:name)} view-job-file #{job.id} FILENAME"}
          ERROR
        elsif sources.length > 1
          raise InputErroor, <<~ERROR.chomp
            Multiple file inputs detected! Please use only one of the following:
            #{pastel.yellow 'FILENAME, --stdout, or --stderr'}
          ERROR
        end

        case sources.first
        when :input
          # NOTE: The following is required for backwards compatibility
          # Future major releases may remove it.
          raise MissingError, <<~ERROR.chomp unless job.output_dir
            The selected job did not report its output directory
          ERROR
          File.join(job.output_dir, args[1])
        when :stdout
          job.stdout_path
        when :stderr
          if job.stdout_path == job.stderr_path
            # TODO: Include the command name once the CLI stabilises
            raise MissingError, <<~ERROR.chomp
              Can not display the standard error as it has been merged with standard out!
            ERROR
          end
          job.stderr_path
        end
      end

      def job
        @job ||= load_job(args.first)
      end
    end
  end
end


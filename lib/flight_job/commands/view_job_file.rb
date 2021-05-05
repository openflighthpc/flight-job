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
    class ViewJobFile < Command
      def run
        # NOTE: The following is required for backwards compatibility
        # Future major releases may remove it.
        raise MissingError, <<~ERROR.chomp unless job.output_dir
          The selected job did not report its output directory
        ERROR

        # Determine the file path
        path = File.join(job.output_dir, args[1])
        raise MissingError, <<~ERROR.chomp unless File.exists?(path)
          The selected file does not exists: #{pastel.yellow path}
        ERROR

        # Display the file
        pager.page File.read(path)
      end

      def job
        @job ||= load_job(args.first)
      end
    end
  end
end


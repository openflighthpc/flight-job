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
    FailedSubmitter = Struct.new(:job) do
      def run
        run!
        return true
      rescue
        Flight.logger.error "Failed to transition job '#{job.id}'"
        Flight.logger.warn $!
        return false
      end

      def run!
        # Check if the maximum pending submission time has elapsed
        start = DateTime.rfc3339(job.created_at).to_time.to_i
        now = Time.now.to_i
        if now - start > FlightJob.config.submission_period
          FlightJob.logger.error <<~ERROR
            The following job is being flagged as FAILED as it has not been submitted: #{job.id}
          ERROR
          job.metadata['job_type'] = "FAILED_SUBMISSION"
          job.metadata['submit_status'] = 128
          job.metadata['submit_stdout'] = ''
          job.metadata['submit_stderr'] = 'Failed to run the submission command for an unknown reason'
          job.metadata.save
        end
      end
    end
  end
end

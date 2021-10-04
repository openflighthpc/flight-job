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
        job = Job.new(id: job_id)
        job.initialize_metadata(script)
        job.submit

        # Patches the submit flag on to output_options
        # NOTE: There is probably a better way to do this in general,
        #       but this is a once off
        show_submit = !job.submitted?
        output_options.merge!(submit: show_submit)

        puts render_output(Outputs::InfoJob, job.decorate)
        unless job.submitted?
          raise GeneralError, "The job submission failed!"
        end
      end

      def script
        @script ||= load_script(args.first)
      end

      private

      def job_id
        NameGenerator.new_job(script.id).next_name
      end
    end
  end
end

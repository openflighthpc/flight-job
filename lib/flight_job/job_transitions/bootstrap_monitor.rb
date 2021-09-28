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
    SUBMITTER_SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["job_type", "version", "id", "results_dir"],
      "properties" => {
        "version" => { "const" => 1 },
        "id" => { "type" => "string", "minLength" => 1 },
        "results_dir" => { "type" => "string", "minLength" => 1 },
        "job_type" => { "enum" => ["SINGLETON", "ARRAY"] }
      }
    })

    BootstrapMonitor = Struct.new(:job) do
      include JobTransitionHelper

      def run
        run!
        return true
      rescue
        Flight.logger.error "Failed to boostrap monitor job '#{job.id}'"
        Flight.logger.warn $!
        return false
      end

      def run!
        # Attempt to parse the stdout for the data
        begin
          data = parse_stdout_json(metadata['submit_stdout'], tag: 'submit')
          validate_data(SUBMITTER_SCHEMA, data, tag: 'submit')
        rescue CommandError
          # The command lied about exiting 0! It did not report the json payload
          # correctly. Changing the status to 128
          job.metadata['job_type'] = 'FAILED_SUBMISSION'
          job.metadata['submit_status'] = 128
          job.metadata["submit_stderr"] << <<~MSG.chomp
            Failed to parse JSON response after the command original exited 0!
          MSG
          job.save_metadata
          raise $!
        end

        # The job was submitted correctly and is now pending
        job.metadata['results_dir'] = data['results_dir']
        job.metadata['scheduler_id'] = data['id']
        job.metadata['job_type'] = data['job_type']

        # Run the monitor
        case data['job_type']
        when 'SINGLETON'
          metadata['state'] = 'PENDING'
          SingletonMonitor.new(job).run
        when 'ARRAY'
          metadata['cancelled'] = false
          metadata['lazy'] = true
          ArrayMonitor.new(job).run
        end
      end
    end
  end
end

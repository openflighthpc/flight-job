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
    BOOTSTRAP_SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["job_type", "version"],
      "properties" => {
        "version" => { "const" => 2 },
        "job_type" => { "enum" => ["SINGLETON", "ARRAY"] }
      }
    })

    BootstrapMonitor = Struct.new(:job) do
      include JobTransitionHelper

      def run
        run!
        return true
      rescue
        Flight.logger.error "Failed to bootstrap monitor job '#{job.id}'"
        Flight.logger.warn $!
        return false
      end

      def run!
        FlightJob.logger.info("Bootstrapping Job: #{job.id}")
        cmd = [FlightJob.config.bootstrap_script_path, job.scheduler_id]
        execute_command(*cmd, tag: 'bootstrap') do |status, stdout, stderr, data|
          raise_command_error unless status.success?

          validate_data(BOOTSTRAP_SCHEMA, data, tag: "bootstrap")
          job.metadata['job_type'] = data['job_type']
          job.metadata['cancelling'] = false

          case data['job_type']
          when 'SINGLETON'
            job.metadata['state'] = 'PENDING'
            SingletonMonitor.new(job).run!
          when 'ARRAY'
            job.metadata['lazy'] = true
            ArrayMonitor.new(job).run!
          end
        end
      end
    end
  end
end

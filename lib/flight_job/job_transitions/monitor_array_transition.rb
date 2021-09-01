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
    class MonitorArrayTransition < SimpleDelegator
      include JobTransitions::JobTransitionHelper

      SCHEMA = JSONSchemer.schema({
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["tasks", "lazy"],
        "properties" => {
          "version" => { "const" => 1 },
          "lazy" => { "type" => "boolean" },
          "tasks" => {
            "type" => "object",
            "additionalProperties" => false, # Redundant, probably ...
            "patternProperties" => {
              # Tasks are validated against the singleton jobs schemas
              ".*" => { "type" => "object" }
            }
          }
        }
      })
      TASK_SCHEMAS = MonitorSingletonTransition::SCHEMAS

      def run
        raise NotImplementedError
      end

      def run!
        FlightJob.logger.info("Monitoring Job: #{id}")
        cmd = [FlightJob.config.monitor_array_script_path, scheduler_id]
        execute_command(*cmd, tag: 'monitor') do |status, stdout, stderr, data|
          if status.success?
            # Validate the output
            validate_data(SCHEMA, data, tag: "monitor-array")
            data['tasks'].each do |index, datum|
              validate_data(TASK_SCHEMAS[:initial], datum, tag: "monitor-array task: #{index} (initial)")
              state = datum['state']
              validate_data(TASK_SCHEMAS[state], datum, tag: "monitor-array task: #{index} (#{state})")
            end

            # Create/Update Each task
            data['tasks'].each do |index, datum|
              process_task(index, datum)
            end

            # Update the lazy flag
            # NOTE: This is deliberately done after the tasks have been updated
            #
            # It is difficult to preform a "transaction" as multiple metadata files
            # are being updated. However it can be reasonable assumed the various
            # updates will succeed, as the response has been validated.
            #
            # Updating the lazy flag at the end gives the monitor a chance to run
            # again if an error has occurred.
            metadata["lazy"] = data["lazy"]
            save_metadata

            # Remove the indexing file in terminal state
            # FileUtils.rm_f active_index_path if terminal?
          end
        end
      end

      private

      def process_task(index, data)
      end

      def parse_time(time, type:)
        return nil if ['', nil].include?(time)
        Time.parse(time).strftime("%Y-%m-%dT%T%:z")
      rescue ArgumentError
        FlightJob.logger.error "Failed to parse #{type}: #{time}"
        FlightJob.logger.debug $!.full_message
        raise_command_error
      end
    end
  end
end

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
        Flight.logger.info("Monitoring array job:#{id}:#{state}:#{job_type}:#{metadata['lazy'].inspect}")
        if !metadata['lazy'].nil? && terminal?
          FlightJob.logger.debug "Skipping monitor for terminated job: #{id}"
          return
        end

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

            # Builds each task
            tasks = data['tasks'].map do |index, datum|
              Task.new(job_id: id, index: index).tap do |task|
                apply_task_attributes(task, datum)
              end
            end

            # Log and raise any invalid tasks
            invalid_tasks = tasks.reject { |t| t.valid?(:save_metadata) }
            unless invalid_tasks.empty?
              invalid_tasks.each do |task|
                FlightJob.logger.error("Failed to save task metadata: #{task.tag}")
                FlightJob.logger.info(errors.full_messages.join("\n"))
              end
              raise InternalError, <<~ERROR.chomp
                Unexpectedly failed to monitor '#{id}' due to invalid task(s)!
              ERROR
            end

            # Save all the tasks metadata
            tasks.each { |t| t.save_metadata(validate: false) }

            # Update the lazy flag
            metadata["lazy"] = data["lazy"]
            save_metadata

            # Remove the indexing file in terminal state
            FileUtils.rm_f active_index_path if terminal?
          end
        end
      end
    end
  end
end

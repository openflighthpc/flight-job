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
    class ArrayMonitor < SimpleDelegator
      include JobTransitions::JobTransitionHelper

      SCHEMA = JSONSchemer.schema({
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["tasks", "lazy"],
        "properties" => {
          "version" => { "const" => 1 },
          "lazy" => { "type" => "boolean" },
          "cancelled" => { "type" => "boolean" },
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
      TASK_SCHEMAS = SingletonMonitor::SCHEMAS

      def run
        FlightJob.logger.info("Monitoring Job: #{id}")
        cmd = [FlightJob.config.monitor_array_script_path, scheduler_id]
        execute_command(*cmd, tag: 'monitor') do |status, stdout, stderr, data|
          if status.success?
            validate_response(data)
            update_tasks(data)
            update_job(data)

            # Remove the indexing file in terminal state
            # FileUtils.rm_f active_index_path if terminal?
          end
        end
      end

      private

      def validate_response(data)
        validate_data(SCHEMA, data, tag: "monitor-array")
        data['tasks'].each do |index, datum|
          validate_data(TASK_SCHEMAS[:common], datum, tag: "monitor-array task: #{index} (common)")
          state = datum['state']
          validate_data(TASK_SCHEMAS[state], datum, tag: "monitor-array task: #{index} (#{state})")
        end
      end

      def update_tasks(data)
        tasks = build_tasks(data)
        assert_tasks_valid(tasks)
        tasks.each { |t| t.save_metadata(validate: false) }
      end

      def update_job(data)
        metadata["cancelled"] = data["cancelled"]
        metadata["lazy"] = data["lazy"]
        save_metadata
      end

      def build_tasks(data)
        data['tasks'].map do |index, datum|
          Task.new(job_id: id, index: index).tap do |task|
            apply_task_attributes(task, datum)
          end
        end
      end

      def assert_tasks_valid(tasks)
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
      end
    end
  end
end

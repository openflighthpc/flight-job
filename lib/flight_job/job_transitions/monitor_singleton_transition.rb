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
    class MonitorSingletonTransition < SimpleDelegator
      include JobTransitions::JobTransitionHelper

      # JSON:Schemer supports oneOf matcher, however this makes the kinda cryptic
      # error messages, super cryptic
      #
      # Instead there is an initial "default" validation, which checks the 'state'
      # is recognized. From that, the more exact validator is selected
      #
      # It is assumed the initial validator is ran before the others
      #
      # NOTE: The time formats are not checked at this validator, as ruby will
      #       attempt to coerce them.
      MONITOR_RESPONSE_SCHEMAS = {
        initial: JSONSchemer.schema({
          "type" => "object",
          "additionalProperties" => true,
          "required" => ["version", "state"],
          "properties" => {
            "version" => { "const" => 1 },
            "state" => { "enum" => Job::STATES }
          }
        }),

        "PENDING" => JSONSchemer.schema({
          "type" => "object",
          "additionalProperties" => false,
          "required" => [],
          "properties" => {
            "version" => {}, "state" => {},
            "scheduler_state" => { "type" => "string", "minLength": 1 },
            "reason" => { "type" => ["string", "null"] },
            "start_time" => { "type" => "null" },
            "end_time" => { "type" => "null" },
            "estimated_start_time" => { "type" => ["string", "null"] },
            "estimated_end_time" => { "type" => ["string", "null"] }
          }
        }),

        "RUNNING" => JSONSchemer.schema({
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["start_time"],
          "properties" => {
            "version" => {}, "state" => {},
            "scheduler_state" => { "type" => "string", "minLength": 1 },
            "reason" => { "type" => ["string", "null"] },
            "start_time" => { "type" => "string", "minLength": 1 },
            "end_time" => { "type" => "null" },
            "estimated_start_time" => { "type" => "null" },
            "estimated_end_time" => { "type" => ["string", "null"] }
          }
        }),

        "COMPLETED" => JSONSchemer.schema({
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["start_time"],
          "properties" => {
            "version" => {}, "state" => {},
            "scheduler_state" => { "type" => "string", "minLength": 1 },
            "reason" => { "type" => ["string", "null"] },
            "start_time" => { "type" => "string", "minLength": 1 },
            "end_time" => { "type" => "string", "minLength": 1 },
            "estimated_start_time" => { "type" => "null" },
            "estimated_end_time" => { "type" => "null" }
          }
        }),

        "CANCELLED" => JSONSchemer.schema({
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["start_time"],
          "properties" => {
            "version" => {}, "state" => {},
            "scheduler_state" => { "type" => "string", "minLength": 1 },
            "reason" => { "type" => ["string", "null"] },
            "start_time" => { "type" => ["null", "string"] },
            "end_time" => { "type" => "string", "minLength": 1 },
            "estimated_start_time" => { "type" => "null" },
            "estimated_end_time" => { "type" => "null" }
          }
        }),

        "UNKNOWN" => JSONSchemer.schema({
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["start_time"],
          "properties" => {
            "version" => {}, "state" => {},
            "scheduler_state" => { "type" => "string", "minLength": 1 },
            "reason" => { "type" => ["string", "null"] },
            "start_time" => { "type" => "null" },
            "end_time" => { "type" => "null" },
            "estimated_start_time" => { "type" => "null" },
            "estimated_end_time" => { "type" => "null" }
          }
        })
      }.tap { |h| h["FAILED"] = h["COMPLETED"] }

      def run
        raise NotImplementedError
      end

      def run!
        # Skip jobs that have terminated, this allows the method to be called liberally
        if Job::STATES_LOOKUP[state] == :terminal
          FlightJob.logger.debug "Skipping monitor for terminated job: #{id}"
          return
        end

        # Jobs without a scheduler ID should not be in a running/pending state. It is
        # an error condition if they are
        unless scheduler_id
          FlightJob.logger.error "Can not monitor job '#{id}' as it did not report its scheduler_id"
          metadata['reason'] = "Did not report it's scheduler ID"
          metadata['state'] = "FAILED"
          File.write(metadata_path, YAML.dump(metadata))
          return
        end

        FlightJob.logger.info("Monitoring Job: #{id}")
        cmd = [FlightJob.config.monitor_script_path, scheduler_id]
        execute_command(*cmd, tag: 'monitor') do |status, stdout, stderr, data|
          if status.success?
            # Validate the output
            validate_data(MONITOR_RESPONSE_SCHEMAS[:initial], data, tag: "monitor (initial)")
            validate_data(MONITOR_RESPONSE_SCHEMAS[data['state']], data, tag: "monitor (#{data['state']})")

            data.each do |key, value|
              # Ignore the metadata version
              next if key == "version"

              # Treat empty string/nil as the same value
              value = nil if value == ''

              # Parse and set times
              if /_time\Z/.match? key
                metadata[key] = parse_time(value, type: key)

              # Set other keys
              else
                metadata[key] = value
              end
            end

            if data['reason'] == ''
              metadata['reason'] = nil
            elsif data['reason']
              metadata['reason'] = data['reason']
            end
            File.write(metadata_path, YAML.dump(metadata))

            # Remove the indexing file in terminal state
            FileUtils.rm_f active_index_path if terminal?
          end
        end
      end

      private

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

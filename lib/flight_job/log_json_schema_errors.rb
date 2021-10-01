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
  LogJSONSchemaErrors = Struct.new(:raw_errors, :levels) do
    def log
      FlightJob.logger.debug("Schema:\n") { JSON.pretty_generate root_schema }
      FlightJob.logger.debug("\n-------------------------------------------------")
      unless other_levels.empty?
        msg = "Other errors logged at: #{other_levels.join(",")}"
        FlightJob.logger.send(priority_level, msg)
      end
      errors.each_with_index do |error, index|
        level = lookup(index)
        Flight.logger.send(level, "Error (#{index + 1}):\n") do
          JSON.pretty_generate(error)
        end
      end
    end

    private

    def root_schema
      raw_errors.first['root_schema']
    end

    def errors
      @errors ||= raw_errors.map do |error|
        error.dup.tap do |copy|
          copy.delete('root_schema')
          schema = copy['schema']

          # Remove the schema if it has been flagged
          if schema.is_a?(Hash) && schema['$comment'] == 'strip-schema'
            copy.delete('schema')
          end

          # Remove the data if there is no data_pointer
          if error["data_pointer"] == ""
            copy.delete("data")
          end
        end
      end
    end

    def priority_level
      @priority_level ||= priority_levels.first
    end

    def other_levels
      priority_levels[1..-1]
    end

    def priority_levels
      @priority_levels ||= if levels.is_a?(Array)
        levels.uniq.sort_by { |l| priority[l] }
       else
        [levels]
       end
    end

    def lookup(index)
      levels.is_a?(Array) ? levels[index] : levels
    end

    def priority
      @priority ||= [
        :fatal, :error, :warn, :info, :debug
      ].each_with_index.to_h
    end
  end
end

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
  class Question < ApplicationModel
    attr_accessor :id, :text, :description, :default, :format, :ask_when, :template, :validate

    def related_question_id
      return nil unless ask_when
      ask_when['value'].split('.')[1]
    end

    def required?
      validate['required']
    end

    def validate_value(value)
      @validate_value ||= JSONSchemer.schema(validate_schema)
      @validate_value.validate(value).map do |error|
        FlightJob.logger.debug("Validation Error '#{id}'") do
          JSON.pretty_generate(error.tap { |e| e.delete('root_schema') })
        end
        [error['schema']['title'].to_sym, error['schema']['description']]
      end
    end

    # Takes the 'validate' key and converts it to the JSON:Schmea
    #
    # NOTE: The schemas must conform to the following conventions:
    # * A 'title' which is used as a generic key to identify the "type" of validation,
    # * A 'description' stores the error message if the validation fails
    def validate_schema
      @validate_schema ||= { 'allOf' => []}.tap do |top_level|
        next unless validate
        allOf = top_level['allOf']

        # Applies the generic type validators
        aOrAn = ['a','e','i','o','u'].include?(validate['type'][0]) ? 'an' : 'a'
        allOf << {
          "type" => [validate['type'], 'null'],
          "title" => "type",
          "description" => "Must be #{aOrAn} #{validate['type']}#{ " or omitted" unless required? }"
        }
        if required?
          allOf << {
            "if" => { "type" => "null" },
            "then" => {
              "type" => validate["type"],
              "title" => "required",
              "description" => "Must not be null"
            }
          }

          # Apply the not empty string validator
          if validate['type'] == 'string'
            allOf << {
              'pattern' => '^.+$',
              'title' => "required",
              'description' => 'Must not be an empty string'
            }
          end
        end

        # Apply the enum validator
        if validate['enum']
          allOf << {
            "enum" => validate["enum"],
            "title" => "enum",
            "description" => "Must be one of the following values: #{validate['enum'].join(',')}"
          }
        end

        # Apply the pattern validator
        if validate['pattern']
          allOf << {
            'pattern' => validate['pattern'],
            "title" => "syntax",
            'description' => validate.fetch('pattern_error', 'Failed the syntax check')
          }
        end

        # Apply the maximum/minimum
        if validate['minimum']
          allOf << {
            "minimum" => validate["minimum"],
            "title" => "minmax",
            "description" => "Must be greater than or equal to #{validate['minimum']}"
          }
        end
        if validate['maximum']
          allOf << {
            "maximum" => validate["maximum"],
            "title" => "minmax",
            "description" => "Must be less than or equal to #{validate['maximum']}"
          }
        end
        if validate['exclusive_minimum']
          allOf << {
            "exclusiveMinimum" => validate["exclusive_minimum"],
            "title" => "minmax",
            "description" => "Must be greater than #{validate['exclusive_minimum']}"
          }
        end
        if validate['exclusive_maximum']
          allOf << {
            "exclusiveMaximum" => validate["exclusive_maximum"],
            "title" => "minmax",
            "description" => "Must be less than #{validate['exclusive_maximum']}"
          }
        end
      end
    end
  end
end

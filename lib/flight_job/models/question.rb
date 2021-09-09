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
      @validate_value ||= JSONSchemer.schema(validate_schema, insert_property_defaults: true)
      @validate_value.validate(value).map do |error|
        FlightJob.logger.debug("Validation Error '#{id}'") do
          JSON.pretty_generate(error.tap { |e| e.delete('root_schema') })
        end
        case error['type']
        when 'type'
          type = error['schema']['type'].first
          if required? && value == nil
            [:required, "Is required"]
          else
            [:type, "Must be a #{type}#{ " or omitted" unless required? }"]
          end
        when 'pattern'
          [:pattern, error['schema']['description']]
        when 'minimum'
          [:minmax, "Must be greater than or equal to #{error['schema']['minimum']}"]
        when 'exclusiveMinimum'
          [:minmax, "Must be greater than #{error['schema']['exclusiveMinimum']}"]
        when 'maximum'
          [:minmax, "Must be less than or equal to #{error['schema']['maximum']}"]
        when 'exclusiveMaximum'
          [:minmax, "Must be less than #{error['schema']['exclusiveMaximum']}"]
        when 'enum'
          [:enum, "Must be one of the following values: #{error['schema']['enum'].join(',')}"]
        else
          FlightJob.logger.error("Could not humanize the following error") do
            JSON.pretty_generate error.tap { |e| e.delete('root_schema') }
          end
          [:unknown, "Could not process error, please check logs"]
        end
      end
    end

    # Takes the 'validate' key and converts it to the JSON:Schmea
    #
    # NOTE: The schemas must conform to the following conventions:
    # * 'type' must be an array of one or two elements
    # * 'type' must have the primary type in the 0th position
    # * 'type' must contain 'null' in the 1st position unless required
    #
    # * 'pattern' matchers must be wrapped in an allOf
    # * 'pattern' matchers must give a 'description' which will be used as the error message
    def validate_schema
      @validate_schema ||= {}.tap do |payload|
        next unless validate
        case validate['type']
        when 'string'
          payload['type'] = ['string']
          payload['type'] << 'null' unless required?
          payload['enum'] = validate['enum'] if validate['enum']
          # The not-blank is enforced via a pattern, this can create a conflict if a pattern
          # is already specified. Hence the pattern matchers are stored within an allOf
          payload['allOf'] = [].tap do |allOf|
            unless required?
              allOf << {
                'pattern' => '^.+$',
                'title' => 'Not Blank',
                'description' => 'Must not be empty string'
              }
            end
            if validate['pattern']
              allOf << {
                'pattern' => validate['pattern'],
                'description' => validate.fetch('pattern_error', 'Failed the syntax check')
              }
            end
          end
        when 'number'
          payload['type'] = ['number']
          payload['type'] << 'null' unless required?
          payload['enum'] = validate['enum'] if validate['enum']
          payload['maximum'] = validate['maximum'] if validate['maximum']
          payload['exclusiveMaximum'] = validate['exclusive_maximum'] if validate['exclusive_maximum']
          payload['minimum'] = validate['minimum'] if validate['minimum']
          payload['exclusiveMinimum'] = validate['exclusive_minimum'] if validate['exclusive_minimum']
        when 'integer'
          payload['type'] = ['integer']
          payload['type'] << 'null' unless required?
          payload['enum'] = validate['enum'] if validate['enum']
          payload['maximum'] = validate['maximum'] if validate['maximum']
          payload['exclusiveMaximum'] = validate['exclusive_maximum'] if validate['exclusive_maximum']
          payload['minimum'] = validate['minimum'] if validate['minimum']
          payload['exclusiveMinimum'] = validate['exclusive_minimum'] if validate['exclusive_minimum']
        when 'boolean'
          payload['type'] = ['boolean']
          payload['type'] << 'null' unless required?
        end
      end
    end
  end
end

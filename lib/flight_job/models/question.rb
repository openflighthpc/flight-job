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
      @validate_value.validate(value).to_a
    end

    # Takes the 'validate' key and converts it to the JSON:Schmea
    def validate_schema
      @validate_schema ||= {}.tap do |payload|
        payload['default'] = default if default
        next unless validate
        case validate['type']
        when 'string'
          payload['type'] = ['string']
          payload['type'] << 'null' unless required?
          payload['enum'] = validate['enum'] if validate['enum']
          # The not-blank is enforced via a pattern, this can create a conflict if a pattern
          # is already specified. Hence the pattern matchers are stored within an allOf
          payload['allOf'] = [].tap do |allOf|
            allOf << { 'pattern' => '^.+$', 'title' => 'Not Blank' } unless required?
            allOf << { 'pattern' => validate['pattern'] } if validate['pattern']
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

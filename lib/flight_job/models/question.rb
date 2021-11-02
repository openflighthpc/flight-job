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
    attr_accessor :id, :text, :description, :ask_when, :template, :validate
    attr_writer :default, :dynamic_default, :format

    def related_question_id
      return nil unless ask_when
      ask_when['value'].split('.')[1]
    end

    def required?
      validate['required']
    end

    def validate_answer(value)
      @validate_validator ||= JSONSchemer.schema(validate_schema )
      @validate_validator.validate(value).map do |error|
        FlightJob.logger.debug("Validation Error '#{id}'") do
          JSON.pretty_generate(error.tap { |e| e.delete('root_schema') })
        end
        # Generate array error messages
        if /\A\/items/.match? error["schema_pointer"]
          [error["schema"]["title"].to_sym, "Value: #{error["data"]} - #{error["schema"]["description"]}"]

        # Generate regular error messages
        else
          [error['schema']['title'].to_sym, error['schema']['description']]
        end
      end
    end

    # Takes the 'validate' key and converts it to the JSON:Schmea
    #
    # NOTE: The schemas must conform to the following conventions:
    # * A 'title' which is used as a generic key to identify the "type" of validation,
    # * A 'description' stores the error message if the validation fails
    def validate_schema
      @validate_schema ||= { "allOf" => [] }.tap do |top_level|
        next unless validate
        allOf = top_level['allOf']

        # Apply non-array validations
        if validate['items'].nil?
          apply_validations(allOf, validate)

        # Apply array validations
        else
          apply_type_validations(allOf, validate)
          top_level["items"] = { "allOf" => [] }

          # The 'required' key doesn't really make sense for array items,
          # It is force set to true so the correct error message is generated
          specs = validate["items"].dup
          specs['required'] = true

          apply_validations(top_level["items"]["allOf"], specs)
        end
      end
    end

    def default
      return @default if @dynamic_default.nil?

      generate(**@dynamic_default) || @default
    end

    def format
      return @format unless @format.key?("dynamic_options")

      f = @format.dup
      dynamic_options = f.delete("dynamic_options")
      f.merge("options" => generate(**dynamic_options))
    end

    def serializable_hash(opts = nil)
      opts ||= {}
      {
        id: id,
        text: text,
        description: description,
        default: default,
        ask_when: ask_when,
        format: format,
        validate: validate_schema,
      }
        .reject { |k, v| v.nil? }
    end

    private

    def generate(**opts)
      QuestionGenerators.call(**opts.symbolize_keys)
    end

    def apply_type_validations(allOf, specs)
      required = specs['required']
      aOrAn = ['a','e','i','o','u'].include?(specs['type'][0]) ? 'an' : 'a'
      allOf << {
        "type" => [specs['type'], 'null'],
        "title" => "type",
        "description" => "Must be #{aOrAn} #{specs['type']}#{ " or omitted" unless required }"
      }
      if required
        allOf << {
          "if" => { "type" => "null" },
          "then" => {
            "type" => specs["type"],
            "title" => "required",
            "description" => "Must not be null"
          }
        }

        # Apply the not empty string validator
        if specs['type'] == 'string'
          allOf << {
            'pattern' => '^.+$',
            'title' => "required",
            'description' => 'Must not be an empty string'
          }
        end
      end
    end

    def apply_validations(allOf, specs)
      apply_type_validations(allOf, specs)

      # Apply the enum validator
      if specs['enum']
        allOf << {
          "enum" => specs["enum"],
          "title" => "enum",
          "description" => "Must be one of the following values: #{specs['enum'].join(',')}"
        }
      end

      # Apply the pattern validator
      if specs['pattern']
        allOf << {
          'pattern' => specs['pattern'],
          "title" => "syntax",
          'description' => specs.fetch('pattern_error', 'Failed the syntax check')
        }
      end

      # Apply the maximum/minimum
      if specs['minimum']
        allOf << {
          "minimum" => specs["minimum"],
          "title" => "minmax",
          "description" => "Must be greater than or equal to #{specs['minimum']}"
        }
      end
      if specs['maximum']
        allOf << {
          "maximum" => specs["maximum"],
          "title" => "minmax",
          "description" => "Must be less than or equal to #{specs['maximum']}"
        }
      end
      if specs['exclusive_minimum']
        allOf << {
          "exclusiveMinimum" => specs["exclusive_minimum"],
          "title" => "minmax",
          "description" => "Must be greater than #{specs['exclusive_minimum']}"
        }
      end
      if specs['exclusive_maximum']
        allOf << {
          "exclusiveMaximum" => specs["exclusive_maximum"],
          "title" => "minmax",
          "description" => "Must be less than #{specs['exclusive_maximum']}"
        }
      end
    end
  end
end

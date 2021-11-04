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

require 'json_schemer'

require_relative '../questions_sort'

module FlightJob
  class Template < ApplicationModel
    VALIDATOR_DEF = {
      "validator_def" => {
        "$comment" => "strip-schema",
        "type" => "object",
        "additionalProperties" => true,
        "required" => ["type"],
        "properties" => {
          # The following keys are properties, however they deliberately partially
          # shadows the JSON:Schema type
          # NOTE: All the types must have a oneOf entry!
          #
          # NOTE: array must be last
          "type" => { "enum" => ["string", "number", "integer", "boolean", "array"] },
        },
        "oneOf" => [
          # String validators
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "type" => { "const" => "string" },
              "required" => { "type" => "boolean" },
              "pattern" => { "type" => "string", "format" => "regex" },
              "pattern_error" => { "type" => "string" },
              "enum" => { "type" => "array", "items" => { "type" => "string" }, "minItems" => 1 }
            },
          },
          # Number validators
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "type" => { "const" => "number" },
              "required" => { "type" => "boolean" },
              "enum" => { "type" => "array", "items" => { "type" => ["number", "integer"], "minItems" => 1 } },
              "minimum" => { "type" => ["number", "integer"] },
              "maximum" => { "type" => ["number", "integer"] },
              "exclusive_minimum" => { "type" => ["number", "integer"] },
              "exclusive_maximum" => { "type" => ["number", "integer"] }
            }
          },
          # Integer validators
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "type" => { "const" => "integer" },
              "required" => { "type" => "boolean" },
              "enum" => { "type" => "array", "items" => { "type" => "integer", "minItems" => 1 } },
              "minimum" => { "type" => "integer" },
              "maximum" => { "type" => "integer" },
              "exclusive_minimum" => { "type" => "integer" },
              "exclusive_maximum" => { "type" => "integer" }
            }
          },
          # Boolean validator
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "type" => { "const" => "boolean" },
              "required" => { "type" => "boolean" }
            }
          },
          # Array validator
          # NOTE: Must be last
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "type" => { "const" => "array" },
              "required" => { "type" => "boolean" },
              "items" => { "$ref" => "#/$defs/array_validator_def" }
            }
          }
        ]
      }
    }

    # Prevent deeply nested arrays
    VALIDATOR_DEF["array_validator_def"] = VALIDATOR_DEF["validator_def"].deep_dup
    VALIDATOR_DEF["array_validator_def"]["properties"]["type"]["enum"].delete("array")
    VALIDATOR_DEF["array_validator_def"]["oneOf"].delete_if { |s| s["properties"]["type"]["const"] == "array" }

    DYNAMIC_DEFAULT_SPEC = {
      "type" => "object",
      "required" => ["type"],
      "properties" => {
        # The following is a field called "type".
        "type" => {
          "type" => "string" ,
          "enum" => [
            "path_placeholder"
          ]
        }
      }
    }

    DYNAMIC_OPTIONS_SPEC = {
      "type" => "object",
      "required" => ['type'],
      "properties" => {
        "type" => {
          "type" => "string" ,
          "enum" => [
            "file_listing"
          ]
        },
        "format_path" => { "enum" => ["absolute", "relative", "basename" ] },
        "glob" => { "type" => "string" },
        "include_null" => { "type" => { "oneof" => ["boolean", "string"] } },
        "directories" => {
          "type" => "array",
          "items" => {
            "type" => "string",
          }
        }
      }
    }

    ASK_WHEN_SPEC = {
      "type" => "object",
      "additionalProperties" => false,
      "required" => ['value', 'eq'],
      "properties" => {
        # NOTE: The question asking mechanism is coupled to the pattern match
        # bellow. They must be updated in tandem
        'value' => { "type" => "string", "pattern" => "^question\.[a-zA-Z_-]+\.answer$" },
        'eq' => { "type" => "string" }
      }
    }

    QUESTION_PROPS_STUB = {
      "id" => {}, "text" => {}, "description" => {}, "dynamic_default" => {},
      "validate" => {}, "ask_when" => {}
    }
    QUESTION_DEF = {
      "question_def" => {
        # Generic top level definition of each format
        "$comment" => "strip-schema",
        "type" => "object",
        "additionalProperties" => true,
        "required" => ["id", "text", "format"],
        "properties" => {
          'id' => { 'type' => 'string' },
          'text' => { 'type' => 'string' },
          "description" => { "type" => "string" },
          'validate' => { "$ref" => "#/$defs/validator_def" },
          'ask_when' => ASK_WHEN_SPEC,
          "dynamic_default" => DYNAMIC_DEFAULT_SPEC,
          "format" => {
            "type" => "object",
            "required" => ["type"],
            "additionalProperties" => true,
            "properties" => {
              'type' => {
                "enum" => [
                  "text", "time", "select", "multiselect", 'multiline_text', 'number'
                ]
              }
            }
          }
        },

        "oneOf" => [
          # (Multi) Text format questions
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              **QUESTION_PROPS_STUB,
              "default" => { "type" => "string" },
              "format" => {
                "type" => "object",
                "additionalProperties" => false,
                "properties" => {
                  "type" => { "const" => "text" }
                }
              }
            }
          },

          # Multi Text format questions
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              **QUESTION_PROPS_STUB,
              "default" => { "type" => "string" },
              "format" => {
                "type" => "object",
                "additionalProperties" => false,
                "properties" => {
                  "type" => { "const" => "multiline_text" }
                }
              }
            }
          },

          # Time format questions
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              **QUESTION_PROPS_STUB,
              # XXX: The default needs to be hardened for this
              "default" => {},
              "format" => {
                "type" => "object",
                "additionalProperties" => false,
                "properties" => {
                  "type" => { "const" => "time" }
                }
              }
            }
          },

          # Number format questions
          # NOTE: By default, HTML <number> only supports integers
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              **QUESTION_PROPS_STUB,
              "default" => { "type" => "integer" },
              "format" => {
                "type" => "object",
                "additionalProperties" => false,
                "properties" => {
                  "type" => { "const" => "number" }
                }
              }
            }
          },

          # Select format questions
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              **QUESTION_PROPS_STUB,
              "default" => { "type" => ["string", "integer", "number"] },
              "format" => {
                "type" => "object",
                "additionalProperties" => false,
                "properties" => {
                  "type" => { "const" => "select" },
                  "options" => {
                    "type" => "array",
                    "items" => {
                      "type" => "object",
                      "additionalProperties" => false,
                      "required" => ["text", "value"],
                      "properties" => {
                        "text" => { "type" => "string" },
                        "value" => { "type" => ["string", "integer", "number"] }
                      }
                    }
                  },
                  "dynamic_options" => DYNAMIC_OPTIONS_SPEC,
                }
              }
            }
          },

          # Multi-select format questions
          {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              **QUESTION_PROPS_STUB,
              "default" => {
                "type" => "array",
                "items" => { "type" => ["string", "integer", "number"] },
              },
              "format" => {
                "type" => "object",
                "additionalProperties" => false,
                "properties" => {
                  "type" => { "const" => "multiselect" },
                  "options" => {
                    "type" => "array",
                    "items" => {
                      "type" => "object",
                      "additionalProperties" => false,
                      "required" => ["text", "value"],
                      "properties" => {
                        "text" => { "type" => "string" },
                        "value" => { "type" => ["string", "integer", "number"] }
                      }
                    }
                  },
                  "dynamic_options" => DYNAMIC_OPTIONS_SPEC,
                }
              }
            }
          }
        ]
      }
    }

    SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "$comment" => "strip-schema",
      "additionalProperties" => false,
      "required" => ['synopsis', 'version', 'generation_questions', 'name', 'copyright', 'license'],
      "properties" => {
        'copyright' => { "type" => "string" },
        'description' => { "type" => 'string' },
        'generation_questions' => {
          "type" => "array",
          "items" => { "$ref" => "#/$defs/question_def" }
        },
        'license' => { "type" => "string" },
        'name' => { "type" => 'string' },
        'priority' => { "type" => 'integer' },
        'script_template' => { "type" => 'string' },
        'synopsis' => { "type" => 'string' },
        'tags' => { "type" => 'array', 'items' => { 'type' => 'string' }},
        'version' => { "type" => 'integer', 'enum' => [0] },
        '__meta__' => {}
      },
      "$defs" => {}.merge!(VALIDATOR_DEF)
                   .merge!(QUESTION_DEF)
    })

    def self.load_all(validate: true)
      templates = Dir.glob(new(id: '*').metadata_path).map do |path|
        id = File.basename(File.dirname(path))
        new(id: id)
      end

      if validate
        templates.select do |template|
          next true if template.valid?
          FlightJob.logger.error("Failed to load missing/invalid template: #{template.id}")
          FlightJob.logger.warn(template.errors.full_messages.join("\n"))
          false
        end

        templates.sort!

        templates.each_with_index do |t, idx|
          t.index = idx + 1
        end

        templates
      else
        templates
      end
    end

    attr_accessor :id, :index

    ONE_OF_VALIDATOR = /\A\/\$defs\/validator_def\/oneOf\/(?<index>\d+)/

    # Validates the metadata and questions file
    validate do
      if metadata
        unless (schema_errors = SCHEMA.validate(metadata).to_a).empty?
          # # Parsers the errors for those with the correct oneOf match
          top_flags = OneOfParser.new(
            'validator_def', 'properties/type',
            /\A\/generation_questions\/\d+\/validate/,
            schema_errors
          ).flags

          # # Re-run the parser for the array validators
          array_flags = OneOfParser.new(
            'array_validator_def', 'properties/type',
            /\A\/generation_questions\/\d+\/validate\/items/,
            schema_errors
          ).flags

          # Re-run the parser for the question format validators
          format_flags = OneOfParser.new(
            'question_def', 'properties/format/properties/type',
            /\A\/generation_questions\/\d+/,
            schema_errors
          ).flags

          # Generate the log levels from the flags:
          # * warn: Errors unrelated to a oneOf
          # * warn: Errors which match a oneOf with the correct type
          # * debug: Errors which failed a oneOf on the wrong type
          levels = top_flags.each_with_index.map do |_, idx|
            flags = [top_flags[idx], array_flags[idx], format_flags[idx]]
            flags.include?(false) ? :debug : :warn
          end

          FlightJob.logger.error("The following metadata file is invalid: #{metadata_path}")
          JSONSchemaErrorLogger.new(schema_errors, levels).log
          errors.add(:metadata, 'is not valid')
        end
      end
    end

    # Validates the workload_path and directives_path
    validate do
      unless File.exists? workload_path
        legacy_path = File.join(FlightJob.config.templates_dir, id, "#{script_template_name}.erb")
        if File.exists?(legacy_path)
          # Symlink the legacy script path into place, if required
          FileUtils.ln_s File.basename(legacy_path), workload_path
        else
          # Otherwise error
          errors.add(:workload_path, "does not exist")
        end
      end
    end

    validate on: :verbose do
      # Ensure the questions are sorted correctly
      begin
        next unless errors.empty?
        sorted = QuestionSort.build(generation_questions).tsort
        unless sorted == generation_questions
          FlightJob.logger.error "The questions for template '#{id}' have not been topographically sorted! A possible sort order is:\n" do
            sorted.map(&:id).join(',')
          end
          errors.add(:questions, 'have not been topographically sorted')
        end
      rescue TSort::Cyclic
        errors.add(:questions, 'form a circular loop')
      rescue UnresolvedReference
        errors.add(:questions, "could not locate referenced question: #{$!.message}")
      rescue
        FlightJob.logger.error "Failed to validate the template questions due to another error: #{id}"
        FlightJob.logger.debug("Error:\n") { $!.message }
        errors.add(:questions, 'could not be validated')
      end
    end

    def exists?
      File.exists? metadata_path
    end

    def metadata_path
      File.join(FlightJob.config.templates_dir, id, "metadata.yaml")
    end

    def workload_path
      File.join(FlightJob.config.templates_dir, id, "workload.erb")
    end

    def directives_path
      File.join(FlightJob.config.templates_dir, id, Flight.config.directives_name)
    end

    def script_template_name
      metadata.fetch('script_template', 'script.sh')
    end

    # NOTE: The raw metadata is exposed through the CLI with the --json flag.
    # This allows it to be directly passed to the API layer.
    # Consider refactoring when introducing a non-backwards compatible change
    def metadata
      return @metadata if defined?(@metadata)
      @metadata = YAML.load(File.read(metadata_path)).to_h
    rescue Errno::ENOENT
      errors.add(:metadata, "has not been saved")
      @metadata = {}
    rescue Psych::SyntaxError
      errors.add(:metadata, "is not valid YAML")
      @metadata = {}
    end

    def serializable_hash(opts = nil)
      opts ||= {}
      {
        'id' => id,
        'path' => workload_path,
        'generation_questions' => generation_questions,
      }.merge(metadata.except("generation_questions")).tap do |hash|
        if Flight.config.includes.include? 'scripts'
          hash['scripts'] = Script.load_all.select { |s| s.template_id == id }
        end
      end
    end

    def generation_questions
      return [] if metadata.nil?
      return [] if metadata['generation_questions'].nil?

      @questions ||= metadata['generation_questions'].map do |datum|
        Question.new(**datum.symbolize_keys)
      end
    end

    def validate_generation_questions_values(hash)
      @validate_generation_questions_values ||= JSONSchemer.schema({
        "type" => "object",
        "additionalProperties" => false,
        "properties" => generation_questions.map { |q| [q.id, {}] }.to_h
      })
      errors = @validate_generation_questions_values.validate(hash).to_a
      {}.tap do |all_errors|
        unless errors.empty?
          all_errors[:root] = []
          errors.each do |error|
            FlightJob.logger.warn("Validation Error 'root-value'") do
              JSON.pretty_generate(error.tap { |e| e.delete('root_schema') })
            end

            if error['schema_pointer'] == '/additionalProperties'
              all_errors[:root] << "Contains an unrecognized key: #{error["data_pointer"][1..-1]}"
            elsif error['type'] == 'object'
              all_errors[:root] << "Must be an object"
            else
              FlightJob.logger.error("Could not humanize the following error") do
                JSON.pretty_generate error.tap { |e| e.delete('root_schema') }
              end
              all_errors[:root] << 'Could not process error, please check the logs'
            end
          end
        end
        if hash.is_a?(Hash)
          generation_questions.each do |q|
            value = hash[q.id]
            all_errors[q.id] = q.validate_answer(value).map { |_, m| m }
          end
        end
      end
    end

    def priority
      metadata['priority']
    end

    def tags
      metadata['tags'] || []
    end

    protected

    def <=>(other)
      if self.priority == other.priority
        self.id <=> other.id
      elsif self.priority.nil?
        1
      elsif other.priority.nil?
        -1
      else
        self.priority <=> other.priority
      end
    end
  end
end

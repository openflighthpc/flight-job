#==============================================================================
# Copyright (C) 2022-present Alces Flight Ltd.
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

module FlightJob
  class Template < ApplicationModel
    module SchemaDefs
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

      SUBMIT_YAML = {
        "type" => "object",
        "$comment" => "strip-schema",
        "additionalProperties" => true,
        "properties" => {
          "scheduler" => {
            "type" => "object",
            "required" => ["args"],
            "properties" => {
              "args" => {
                "type": "array",
                "items" => { "type" => "string" }
              }
            }
          },
          "job_script" => {
            "type" => "object",
            "required" => ["args"],
            "properties" => {
              "args" => {
                "type": "array",
                "items" => { "type" => "string" }
              }
            }
          }
        }
      }.freeze
    end
  end
end

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
require 'json'
require 'json_schemer'
require_relative "../metadata/base_metadata"
require_relative "../../validators/json_schema_validator"

module FlightJob
  class Template < ApplicationModel
    # Encapsulates a template's `metadata.yaml` file.
    #
    # * Loads and saves the file.
    # * Validates against a schema.
    class Metadata < Metadata::BaseMetadata

      SCHEMA = JSONSchemer.schema({
        "type" => "object",
        "$comment" => "strip-schema",
        "additionalProperties" => false,
        "required" => %w(
          synopsis
          version
          generation_questions
          name
          copyright
          license
        ),
        "properties" => {
          "copyright" => { "type" => "string" },
          "description" => { "type" => "string" },
          "generation_questions" => {
            "type" => "array",
            "items" => { "$ref" => "#/$defs/question_def" }
          },
          "submission_questions" => {
            "type" => "array",
            "items" => { "$ref" => "#/$defs/question_def" }
          },
          "license" => { "type" => "string" },
          "name" => { "type" => "string" },
          "priority" => { "type" => "integer" },
          "script_template" => { "type" => "string" },
          "synopsis" => { "type" => "string" },
          "tags" => { "type" => "array", "items" => { "type" => "string" }},
          "version" => { "type" => "integer", "enum" => [0] },
          "__meta__" => {}
        },
        "$defs" => {}.merge!(SchemaDefs::VALIDATOR_DEF).merge!(SchemaDefs::QUESTION_DEF)
      })

      attributes \
        :copyright,
        :license,
        :name,
        :description,
        :synopsis,
        :generation_questions,
        :submission_questions,
        :script_template,
        :priority,
        :version,
        :__meta__

      attribute :tags, default: []

      def exists?
        File.exist?(@path)
      end

      def fetch(key, default = nil)
        @hash.fetch(key, default)
      end
    end
  end
end

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
  class Script < ApplicationModel
    # Encapsulates a script's `metadata.yaml` file.
    #
    # * Loads and saves the file.
    # * Validates against a schema.
    class Metadata < Metadata::BaseMetadata

      SCHEMA = JSONSchemer.schema({
        "$comment" => "strip-schema",
        "type" => "object",
        "additionalProperties" => false,
        "required" => ['created_at', 'script_name'],
        "properties" => {
          # ----------------------------------------------------------------------------
          # Required
          # ----------------------------------------------------------------------------
          'created_at' => { 'type' => 'string', 'format' => 'date-time' },
          'script_name' => { 'type' => 'string' },
          # ----------------------------------------------------------------------------
          # Psuedo - Required
          #
          # These should *probably* become required on the next major release of the metadata
          # ----------------------------------------------------------------------------
          'answers' => { 'type' => 'object' },
          'tags' => { 'type' => 'array', 'items' => { 'type' => 'string' }},
          'template_id' => { 'type' => 'string' },
          'version' => { 'const' => 0 },
        }
      })

      validates_with JsonSchemaValidator,
                     schema: SCHEMA,
                     json_method: :to_hash,
                     error_key: :metadata

      attributes \
        :created_at,
        :tags,
        :template_id,
        :script_name

      attribute :answers, default: {}

      def self.from_template(template, answers, script)
        initial_metadata = {
          "version" => 0,
          "created_at" => Time.now.rfc3339,
          "template_id" => template.id,
          "script_name" => template.script_template_name,
          "answers" => answers,
          "tags" => template.tags,
        }
        new(initial_metadata, script.metadata_path, script)
      end

      def self.blank(path, parent)
        initial_metadata = {
          "version" => 0,
          "created_at" => Time.now.rfc3339
        }
        new(initial_metadata, path, parent)
      end

      def persisted?
        # Sometimes we render a script that has no ID; in this case, it doesn't
        # exist outside of the execution scope, and will not have a path.
        return nil if @path.nil?
        File.exist?(@path)
      end
    end
  end
end

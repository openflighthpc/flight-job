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

      validate do
        schema_errors = SCHEMA.validate(self.to_hash).to_a
        unless schema_errors.empty?
          path_tag = File.exist?(@path) ? @path : @parent.id
          FlightJob.logger.info("Invalid metadata: #{path_tag}\n")
          JSONSchemaErrorLogger.new(schema_errors, :info).log
          errors.add(:metadata, 'is not valid')
        end
      end

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

      def tags=(tags)
        @hash["tags"] = tags
      end

      def template_id=(id)
        @hash['template_id'] = id
      end

      def script_name=(name)
        @hash['script_name'] = name
      end

      def answers=(object)
        @answers['answers'] = object
      end

    end
  end
end

#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
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
    FORMAT_SPEC = {
      "type" => "object",
      "additionalProperties" => false,
      "required" => ['type'],
      "properties" => {
        'type' => { "type" => "string" },
        'options' => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => ['text', 'value'],
            "properties" => {
              'text' => { "type" => "string" },
              'value' => { "type" => "string" }
            }
          }
        }
      }
    }

    ASK_WHEN_SPEC = {
      "type" => "object",
      "additionalProperties" => false,
      "required" => ['value', 'eq'],
      "properties" => {
        'value' => { "type" => "string" },
        'eq' => { "type" => "string" }
      }
    }

    QUESTIONS_SPEC = {
      "type" => "array",
      "items" => {
        "type" => "object",
        "additionalProperties" => false,
        "required" => ['id', 'text'],
        "properties" => {
          'id' => { 'type' => 'string' },
          'text' => { 'type' => 'string' },
          'description' => { 'type' => 'string' },
          # NOTE' => Forcing the default to be a string is a stop-gap measure
          # It keeps the initial implementation simple as everything is a strings
          # Eventually multiple formats will be supported
          'default' => { 'type' => 'string' },
          'format' => FORMAT_SPEC,
          'ask_when' => ASK_WHEN_SPEC
        }
      }
    }

    SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ['synopsis', 'version', 'generation_questions', 'name'],
      "properties" => {
        'name' => { "type" => 'string' },
        'script_template' => { "type" => 'string' },
        'synopsis' => { "type" => 'string' },
        'description' => { "type" => 'string' },
        'version' => { "type" => 'integer', 'enum' => [0] },
        'generation_questions' => QUESTIONS_SPEC
      }
    })

    def self.load_all(validate: true)
      templates = Dir.glob(new(id: '*').metadata_path).map do |path|
        id = File.basename(File.dirname(path))
        new(id: id)
      end

      if validate
        templates.select do |template|
          next true if template.valid?
          FlightJob.logger.warn "Rejecting invalid template: #{template.id}"
          FlightJob.logger.debug("Errors: \n") { template.errors }
          false
        end
      else
        templates
      end
    end

    attr_accessor :id, :index

    # Validates the metadata and questions file
    validate do
      if metadata
        unless (schema_errors = SCHEMA.validate(metadata).to_a).empty?
          FlightJob.logger.error("The following metadata file is invalid: #{metadata_path}")
          FlightJob.logger.debug "Errors:\n" do
            schema_errors.each_with_index.map do |error, index|
              "Error #{index + 1}:\n#{JSON.pretty_generate(error)}"
            end.join("\n")
          end
          errors.add(:metadata, 'is not valid')
        end
      end
    end

    # Validates the script
    validate do
      unless File.exists? template_path
        errors.add(:template, "has not been saved")
      end
    end

    def metadata_path
      File.join(FlightJob.config.templates_dir, id, "metadata.yaml")
    end

    def template_path
      File.join(FlightJob.config.templates_dir, id, "#{script_template_name}.erb")
    end

    def script_template_name
      metadata.fetch('script_template', 'script.sh')
    end

    # NOTE: The metadata is intentionally cached to prevent excess file reads during
    # serialization. This cache is not intended to be reset, instead a new Template
    # instance should be initialized.
    def metadata
      @metadata ||= begin
        YAML.load(File.read(metadata_path)).to_h
      end
    rescue Errno::ENOENT
      errors.add(:metadata, "has not been saved")
      {}
    rescue Psych::SyntaxError
      errors.add(:metadata, "is not valid YAML")
      {}
    end

    def questions_data
      return [] if metadata.nil?
      metadata['generation_questions']
    end

    def generation_questions
      @questions ||= questions_data.map do |datum|
        Question.new(**datum.symbolize_keys)
      end
    end

    def to_erb
      ERB.new(File.read(template_path), nil, '-')
    end
  end
end

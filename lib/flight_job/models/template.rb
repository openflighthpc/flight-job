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

require "json_schemer"

require_relative "template/validator"
require_relative "template/schema_defs"

module FlightJob
  class Template < ApplicationModel
    SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "$comment" => "strip-schema",
      "additionalProperties" => false,
      "required" => [
        "synopsis",
        "version",
        "generation_questions",
        "name",
        "copyright",
        "license"
      ],
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

    def self.load_all
      templates = Dir.glob(new(id: '*').metadata_path).map do |path|
        id = File.basename(File.dirname(path))
        new(id: id)
      end

      templates.each do |template|
        next if template.valid?
        FlightJob.logger.warn("Invalid template detected upon load: #{template.id}")
        FlightJob.logger.warn(template.errors.full_messages.join("\n"))
      end

      templates.sort!

      templates.each_with_index do |t, idx|
        t.index = idx + 1
      end

      templates
    end

    attr_accessor :id, :index

    ONE_OF_VALIDATOR = /\A\/\$defs\/validator_def\/oneOf\/(?<index>\d+)/

    validates_with Template::Validator

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

    # XXX Wanted???
    def submit_yaml_path
      File.join(FlightJob.config.templates_dir, id, 'submit.yaml.erb')
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

      @_generation_questions ||= metadata['generation_questions'].map do |datum|
        Question.new(**datum.symbolize_keys)
      end
    end

    # XXX Copy this to the script???
    def submission_questions
      return [] if metadata.nil?
      return [] if metadata['submission_questions'].nil?

      @_submission_questions ||= metadata['submission_questions'].map do |datum|
        Question.new(**datum.symbolize_keys)
      end
    end

    def without_defaults
      # Get all questions with no default key specified. Default keys with an
      # empty string value are allowed, as it's probably intended.
      generation_questions.select do |gq|
        gq.default.nil?
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

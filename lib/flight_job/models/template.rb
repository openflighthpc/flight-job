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
    FORMAT_SPEC = {
      "type" => "object",
      "additionalProperties" => false,
      "required" => ['type'],
      "properties" => {
        # The following are field called "type" and "options" not settings within "properties"
        'type' => { "type" => "string" , "enum" => [
          "text", "time", "select", "multiselect", 'multiline_text'
        ] },
        'options' => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => ['text', 'value'],
            "properties" => {
              'text' => { "type" => "string" },
              'value' => { "type" => "string" },
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
        # NOTE: The question asking mechanism is coupled to the pattern match
        # bellow. They must be updated in tandem
        'value' => { "type" => "string", "pattern" => "^question\.[a-zA-Z_-]+\.answer$" },
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
          'default' => {},
          'format' => FORMAT_SPEC,
          'ask_when' => ASK_WHEN_SPEC
        },
        "if" => { "properties" => { "format" => {
          "type" => "object",
          # NOTE: The following "type" is the name of the property NOT a declaration
          "properties" => { "type" => { "const" => "multiselect" } }
        } } },
        "then" => { "properties" => {
          "default" => { "type" => "array", "items" => { "type" => "string" } }
        } },
        "else" => { "properties" => {
          "default" => { "type" => "string" }
        } }
      }
    }

    SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ['synopsis', 'version', 'generation_questions', 'name', 'copyright', 'license'],
      "properties" => {
        'copyright' => { "type" => "string" },
        'description' => { "type" => 'string' },
        'generation_questions' => QUESTIONS_SPEC,
        'license' => { "type" => "string" },
        'name' => { "type" => 'string' },
        'priority' => { "type" => 'integer' },
        'script_template' => { "type" => 'string' },
        'synopsis' => { "type" => 'string' },
        'tags' => { "type" => 'array', 'items' => { 'type' => 'string' }},
        'version' => { "type" => 'integer', 'enum' => [0] },
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
          FlightJob.logger.error("Failed to load missing/invalid template: #{id}")
          FlightJob.logger.info(template.errors.full_messages.join("\n"))
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

      unless File.exists? directives_path
        errors.add(:directives_path, "does not exist")
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
        FlightJob.logger.debug("Error:\n") { $!.messages }
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

    def serializable_hash(opts = nil)
      opts ||= {}
      {
        'id' => id,
        'path' => workload_path,
      }.merge(metadata).tap do |hash|
        if Flight.config.includes.include? 'scripts'
          # NOTE: Consider using a file registry instead
          hash['scripts'] = Script.load_all.select { |s| s.template_id == id }
        end
      end
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

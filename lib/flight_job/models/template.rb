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

require_relative "template/schema_defs"
require_relative "template/validator"
require_relative '../matcher'
require_relative 'template/metadata'

module FlightJob
  class Template < ApplicationModel

    def self.load_all(opts = nil)
      Dir.glob(new(id: '*').metadata_path).map do |path|
        id = File.basename(File.dirname(path))
        template = new(id: id)
        unless template.valid?
          FlightJob.logger.warn("Invalid template detected upon load: #{template.id}")
          FlightJob.logger.warn(template.errors.full_messages.join("\n"))
        end
        template
      end.sort
         .each_with_index { |t, idx| t.index = idx + 1 }
         .select { |t| t.pass_filter?(opts) }
    end

    attr_accessor :id, :index

    delegate(*Metadata.attribute_names - %i[generation_questions submission_questions], to: :metadata)
    delegate :exists?, to: :metadata

    validates_with Template::Validator

    validate do
      unless submit_args.valid?
        messages = submit_args.errors.map { |e| e.message }
        errors.add(:rendred_submit_yaml_erb, messages.join("; "))
      end
    end

    def pass_filter?(filters)
      @_matcher ||= Matcher.new(filters, {id: id, name: name})
      @_matcher.matches?
    end

    def metadata_path
      File.join(FlightJob.config.templates_dir, id, "metadata.yaml")
    end

    def workload_path
      File.join(FlightJob.config.templates_dir, id, "workload.erb")
    end

    def default_notes
      File.join(FlightJob.config.templates_dir, id, "notes.md")
    end
    
    def directives_path
      File.join(FlightJob.config.templates_dir, id, Flight.config.directives_name)
    end

    def script_template_name
      metadata.script_template || 'script.sh'
    end

    def metadata
      @metadata ||= if File.exist?(metadata_path)
                      Metadata.load_from_path(metadata_path, self)
                    else
                      errors.add(:metadata, "has not been saved")
                      Metadata.blank(metadata_path, self)
                    end
    end

    def serializable_hash(opts = nil)
      opts ||= {}
      md = metadata.except("generation_questions", "submission_questions", "__meta__")
      md.merge(
        'id' => id,
        'path' => workload_path,
        'generation_questions' => generation_questions,
        'submission_questions' => submission_questions,
      ).tap do |hash|
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
      validate_questions_values(generation_questions, hash)
    end

    def validate_submission_questions_values(hash)
      validate_questions_values(submission_questions, hash)
    end

    def validate_questions_values(questions, hash)
      schema = JSONSchemer.schema({
        "type" => "object",
        "additionalProperties" => false,
        "properties" => questions.map { |q| [q.id, {}] }.to_h
      })
      errors = schema.validate(hash).to_a
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
          questions.each do |q|
            value = hash[q.id]
            all_errors[q.id] = q.validate_answer(value).map { |_, m| m }
          end
        end
      end
    end

    def generate_submit_args(job)
      submit_args.render_and_save(job)
    end

    def submit_args
      @_submit_args ||= SubmitArgs.new(template: self)
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

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

require "json_schemer"

require_relative "../validators/json_schema_validator"

module FlightJob
  # Encapsulates a template's `submit.yaml.erb` file.
  #
  # * Validates the file against a schema.
  # * Renders it with some user provided answers.
  # * Stores a copy of the render.
  class SubmitArgs < ApplicationModel

    # Provides access to the render result without exposing its structure.
    class RenderResult
      delegate :to_yaml, to: :@hash

      def initialize(hash)
        @hash = hash
      end

      def scheduler_args
        @hash.dig("scheduler", "args")
      end

      def job_script_args
        @hash.dig("job_script", "args")
      end
    end

    SCHEMA = JSONSchemer.schema({
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
    })

    DEFAULT_SUBMIT_ARGS = {
      "scheduler" => { "args" => [] },
      "job_script" => { "args" => [] },
    }.freeze

    delegate :submission_questions, to: :template

    attr_accessor :template

    validates_with JsonSchemaValidator,
      schema: SCHEMA,
      json_method: :render_raw,
      error_key: :rendred_submit_yaml

    def template_path
      File.join(FlightJob.config.templates_dir, template.id, 'submit.yaml.erb')
    end

    def render_raw(answers={})
      return DEFAULT_SUBMIT_ARGS.dup unless File.exist?(template_path)

      renderer = FlightJob::Renderers::SubmitArgsRenderer.new(
        answers: answers,
        questions: template.submission_questions,
        template_path: template_path,
      )
      YAML.load(renderer.render)
    rescue Psych::SyntaxError
      errors.add(:rendred_submit_yaml, "is not valid YAML")
    end

    def render(answers)
      RenderResult.new(render_raw(answers))
    end

    def render_and_save(job)
      render(job.submission_answers).tap do |args|
        File.write(File.join(job.job_dir, 'submit.yaml'), args.to_yaml)
      end
    end
  end
end

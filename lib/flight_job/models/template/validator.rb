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

require_relative 'questions_sort'

module FlightJob
  class Template < ApplicationModel
    class Validator < ActiveModel::Validator
      def validate(template)
        validate_schema(template)
        validate_paths(template)
        validate_question_sort_order(template, :generation_questions)
        validate_question_sort_order(template, :submission_questions)
      end

      private

      def validate_schema(template)
        return unless template.metadata.present?
        schema_errors = SCHEMA.validate(template.metadata).to_a
        return if schema_errors.empty?

        template.errors.add(:metadata, 'is not valid')
        log_errors(template, schema_errors)
      end

      # This isn't really validation, more of a migration, but we want to run
      # it every time a template loads.
      #
      # XXX Extract to an `on_loaded` hook/callback?  Or perhaps to a
      # migration?
      def validate_paths(template)
        # Originally, templates had their directives and workload in the same
        # file at `legacy_path`.  Now they have their workload in file at
        # `template.workload_path` and optionally have their directives in
        # another file.
        #
        # After this migration/validation runs `template.workload_path` will
        # exist or validation will fail.
        return if File.exist?(template.workload_path)

        legacy_path = File.join(FlightJob.config.templates_dir, template.id, "#{template.script_template_name}.erb")
        if File.exist?(legacy_path)
          # Symlink the legacy script path into place, if required
          FileUtils.ln_s(File.basename(legacy_path), template.workload_path)
        else
          # Otherwise error
          template.errors.add(:workload_path, "does not exist")
        end
      end

      # A template's questions can depend on the answer to other questions.
      # We validate here that (1) dependencies are not cyclic; and (2) the
      # order of the questions in the metadata file asks dependant questions
      # after their dependencies have been asked.
      def validate_question_sort_order(template, question_type)
        return unless template.errors.empty?

        questions = template.send(question_type)
        begin
          sorted = QuestionSort.build(questions).tsort
          unless sorted == questions
            msg = "The #{question_type} for template '#{template.id}' are " \
              "not been correctly sorted. A possible sort order is:\n" 
            FlightJob.logger.error(msg) { sorted.map(&:id).join(', ') }
            errors.add(question_type, 'are not correctly sorted')
          end
        rescue TSort::Cyclic
          template.errors.add(question_type, 'form a circular loop')
        rescue QuestionSort::UnresolvedReference
          template.errors.add(question_type, "could not locate referenced question: #{$!.message}")
        rescue
          FlightJob.logger.error "Failed to validate the template #{question_type} due to another error: #{template.id}"
          FlightJob.logger.debug("Error:\n") { $!.message }
          template.errors.add(question_type, 'could not be validated')
        end
      end

      # Log a useful and concise error message at an appropriate log level.
      def log_errors(template, schema_errors)
        # This is surprisingly awkward to acheive, especially given the
        # "fluid" nature for the schema.  For instance, consider the
        # question's `validate` object: which keys are valid depend on the
        # *value* of the `type` key.
        #
        # We can validate that object by using JSON Schema's, one of parser to
        # validate the different "flavours" that the `validate` object might
        # match.  If none match, we're left trying to figure out which one the
        # user was attempting to match, so that we can give a useful and
        # concise erorr message.
        #
        # In short: here by dragons.

        # Errors caught on any `generation_questions.validate` objects.
        q_validate_flags = OneOfParser.new(
          'validator_def', 'properties/type',
          /\A\/(generation)|(submission)_questions\/\d+\/validate/,
          schema_errors
        ).flags

        # Errors caught on any `generation_questions.validate.items` objects.
        q_validate_item_flags = OneOfParser.new(
          'array_validator_def', 'properties/type',
          /\A\/(generation)|(submission)_questions\/\d+\/validate\/items/,
          schema_errors
        ).flags

        # Errors caught on any `generation_questions.format.type` objects.
        q_format_flags = OneOfParser.new(
          'question_def', 'properties/format/properties/type',
          /\A\/(generation|submission)_questions\/\d+/,
          schema_errors
        ).flags

        # Generate the log levels from the flags.  There are three cases.
        #
        # 1. There are errors unrelated to a oneOf.
        # 2. We know which oneOf the user was attempting (i.e., they got
        #    `validate.type` correct).
        # 3. We don't know which one oneOf the user was attempting (i.e., they
        #    got `validate.type` incorrect).
        #
        # For (1) and (2) we log at level `warn`.  For (3) we log at `debug`
        # as there is likely to be a lot of failed oneOf matchers.  We don't
        # want to drown the user in too much irrelevant logs.
        log_level = q_validate_flags.each_with_index.map do |_, idx|
          flags = [q_validate_flags[idx], q_validate_item_flags[idx], q_format_flags[idx]]
          flags.include?(false) ? :debug : :warn
        end

        FlightJob.logger.error("The following metadata file is invalid: #{template.metadata_path}")
        JSONSchemaErrorLogger.new(schema_errors, log_level).log
      end
    end
  end
end

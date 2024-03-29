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

require_relative "concerns/answers_options_concern"

module FlightJob
  module Commands
    class CreateScript < Command
      include Concerns::AnswersOptionsConcern

      def run
        # The script_id, answers and notes can be provided in a number of
        # different ways.  Including two that we consider to be user errors.
        #
        # First the two error conditions:
        #
        # 1. Stdin is being used to provide both the notes and the answers.
        # 2. Stdin is being used, and the answers have not been provided.
        #
        # Now the legitimate ways of providing the inputs.
        #
        # 3. They can all be given on the command line.
        # 4. The answers OR notes but NOT both can be read from stdin.
        # 5. The user can be interactively prompted for them.  This requires
        #    stdin to not already be used and for stdout to be a TTY.
        # 6. The defaults can be used.
        #
        # The branches below cover all of these cases.

        script =
          if answers_provided_on_stdin? && notes_provided_on_stdin?
            # Refuse an attempt to read both the notes and the answers from
            # stdin.
            raise InputError, <<~ERROR.chomp
              Cannot use standard input to provide both the answers and the notes!
            ERROR

          elsif stdin_used? && !answers_provided?
            # Answers have not been provided, but stdin has been used
            # (presumably to provide the notes).  We could use the defaults
            # for the answers.  However, we refuse this particular way of
            # calling Flight Job for legacy reasons.
            raise InputError, <<~ERROR.chomp
              Cannot prompt for the answers as standard input is in use!
              Please provide the answers with the following flag: #{pastel.yellow '--answers'}
            ERROR

          elsif answers_provided? && notes_provided? && script_id_provided?
            # All inputs have been provided either via command line argument or
            # read from stdin.  There is nothing to prompt for.
            create_script(script_id, answers, notes)

          elsif stdin_used? && answers_provided?
            # We have answers.  We may or may not have the notes, but they can
            # be provided after the fact.  We may or may not have a script_id,
            # if not, we will use a generated one.
            create_script(script_id || default_id, answers, notes || "")

          elsif $stdout.tty?
            # We're missing something.  It could be the answers, the notes, or
            # the script_id.  Either way, stdin is not used and stdout is a
            # TTY, so we can prompt for what's missing.
            run_prompter(script_id || default_id, answers || {}, notes || "")

          else
            # We may or may not have answers, a script_id or notes.  We use
            # the (hopefully) sensible defaults if they are missing.
            unless answers_provided?
              msg = "No answers have been provided. Proceeding with the defaults."
              $stderr.puts pastel.red(msg)
              FlightJob.logger.warn msg
            end
            create_script(script_id || default_id, answers || {}, notes || "")
          end

        puts render_output(Outputs::InfoScript, script)
      end

      private

      def run_prompter(script_id, answers, notes)
        prompter = Prompters::ScriptCreationPrompter.new(
          pastel,
          pager,
          questions,
          answers,
          script_id,
          notes
        )
        prompter.call
        create_script(prompter.id, prompter.answers, prompter.notes)
      end

      def create_script(script_id, answers, notes)
        verify_id(script_id) if script_id
        opts = ( script_id ? { id: script_id } : {} )
        script = Script.new( **opts )
        script.initialize_notes(notes)
        script.initialize_metadata(template, answers)
        script.render_and_save
        script
      end

      def template
        @_template ||= load_template(args.first).tap do |t|
          unless t.valid?
            FlightJob.logger.debug("Missing/invalid template: #{t.id}\n") do
              t.errors.full_messages.join("\n")
            end
            raise MissingTemplateError, "Could not locate template: #{t.id}"
          end
        end
      end

      def stdin_used?
        notes_provided_on_stdin? || answers_provided_on_stdin?
      end

      def script_id_provided?
        !script_id.nil?
      end

      def script_id
        args.length > 1 ? args[1] : nil
      end

      def default_id
        generator = NameGenerator.new_script(template.id)
        generator.base_name || generator.backfill_name
      end

      def notes_provided?
        !notes.nil?
      end

      def notes_provided_on_stdin?
        stdin_flag?(opts.notes)
      end

      def notes
        if opts.notes
          if notes_provided_on_stdin?
            cached_stdin
          elsif opts.notes[0] == '@'
            read_file(opts.notes[1..])
          else
            opts.notes
          end
        else
          File.file?(template.default_notes) ? read_file(template.default_notes) : nil
        end
      end

      # Checks if the script's ID is valid
      def verify_id(id)
        script = Script.new(id: id)
        return if script.valid?(:id_check)

        # Find the first error related to the ID.
        # There may be more than one error, but the first one determines the
        # exit code. The error log will contain the full list
        error = script.errors.find { |e| e.attribute == :id }
        return unless error
        FlightJob.logger.error("The script is invalid:\n") do
          script.errors.full_messages.join("\n")
        end

        # Determine the exit code from the cause
        if error.type == :already_exists
          script.raise_duplicate_id_error
        else
          raise InputError, "The ID #{error.message}!"
        end
      end

      def questions
        template.generation_questions
      end

      def validate_answers(hash)
        template.validate_generation_questions_values(hash)
      end
    end
  end
end

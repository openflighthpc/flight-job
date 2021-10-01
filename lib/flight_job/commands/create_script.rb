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

require 'json'
require 'tempfile'

module FlightJob
  module Commands
    class CreateScript < Command
      def run
        # Stashes the preliminary version of the name
        # NOTE: It is validated latter
        name = args.length > 1 ? args[1] : nil

        # Attempt to get the answers/notes from the input flags
        answers = answers_input
        notes = notes_input

        # Skip this section if all the fields have been provided
        if answers && notes && name
          # NOOP

        # Handle STDIN contention (disables the prompts)
        elsif stdin_answers? || stdin_notes?
          raise InputError, <<~ERROR.chomp if answers.nil?
            Cannot prompt for the answers as standard input is in use!
            Please provide the answers with the following flag: #{pastel.yellow '--answers'}
          ERROR
          notes ||= ''

        # Prompt for this missing answers/notes/name
        elsif $stdout.tty?
          prompter = QuestionPrompter.new(pastel, pager, template.generation_questions, notes || '', name)
          prompter.prompt_invalid_name
          prompter.prompt_all if answers.nil?
          prompter.prompt_loop

        # Populate missing answers/notes in a non-interactive shell
        else
          answers ||= begin
            msg = "No answers have been provided! Proceeding with the defaults."
            $stderr.puts pastel.red(msg)
            FlightJob.logger.warn msg
            {}
          end
          notes ||= ''
        end

        # Create the script from the prompter
        script = nil
        if prompter
          begin
            script = render_and_save(prompter.name, prompter.answers, prompter.notes)
          rescue DuplicateError
            # Retry if the name was taken before it could be saved
            prompter.prompt_invalid_name
            prompter.prompt_loop
            retry
          end
        # Create the script from the manual inputs
        else
          script = render_and_save(name, answers, notes)
        end

        # Render the script output
        puts render_output(Outputs::InfoScript, script)
      end

      def render_and_save(name, answers, notes)
        # Ensure the ID is valid
        verify_id(name) if name
        ScriptCreator.new(
          id: name,
          answers: answers,
          notes: notes,
          template: template
        )
          .call
      end

      def template
        @template ||= load_template(args.first).tap do |t|
          unless t.valid?
            FlightJob.logger.debug("Missing/invalid template: #{t.id}\n") do
              t.errors.full_messages.join("\n")
            end
            raise MissingTemplateError, "Could not locate template: #{t.id}"
          end
        end
      end

      def stdin_notes?
        stdin_flag?(opts.notes)
      end

      def stdin_answers?
        if opts.stdin
          true
        elsif opts.answers
          stdin_flag?(opts.answers)
        else
          false
        end
      end

      def notes_input
        return unless opts.notes
        if stdin_notes?
          cached_stdin
        elsif opts.notes[0] == '@'
          read_file(opts.notes[1..])
        else
          opts.notes
        end
      end

      def answers_input
        return unless opts.stdin || opts.answers
        string = if stdin_answers?
                   cached_stdin
                 elsif opts.answers[0] == '@'
                   read_file(opts.answers[1..])
                 else
                   opts.answers
                 end
        JSON.parse(string).tap do |hash|
          raise InputError, 'The answers are not a JSON hash' unless hash.is_a?(Hash)
        end
      rescue JSON::ParserError
        raise InputError, <<~ERROR.chomp
          Failed to parse the answers as they are not valid JSON:
          #{$!.message}
        ERROR
      end

      # Checks if the script's ID is valid
      def verify_id(id)
        script = Script.new(id: id)
        return if script.valid?(:id_check)

        # Find the first error related to the ID
        # NOTE: There maybe more than one error, but the first one determines the
        #       exit code. The error log will contain the full list
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
    end
  end
end

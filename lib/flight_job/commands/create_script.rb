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
require 'tty-prompt'
require 'tempfile'

module FlightJob
  module Commands
    class CreateScript < Command
      MULTI_HELP = "(Press ↑/↓/←/→ arrow to scroll, Space/Ctrl+A|R to select (all|rev) and Enter to finish)"
      SUMMARY = ERB.new(<<~'TEMPLATE', nil, '-')
        <%= pastel.bold.underline 'SUMMARY' %>

        <%= pastel.bold 'Name: ' -%><%= pastel.red '(To Be Determined)' %>

        <%= pastel.bold 'Answers:' %>
        <% questions.each do |question| -%>
        <% next unless asked[question.id] -%>
        <%= pastel.bold.cyan(question.text) %>
        <%
          value = answers[question.id]
          value = (value.is_a?(Array) ? value.join(',') : value.to_s)
        -%>
        <%= (value.empty? ? pastel.red('(none)') : pastel.green(value)) %>
        <% end -%>

        <%= pastel.bold 'Notes:' %>
        <%= (notes.to_s.empty? ? pastel.red('(none)') : pastel.green(notes)) %>

      TEMPLATE

      # NOTE: The questions must be topologically sorted on their dependencies otherwise
      # these prompts will not function correctly
      QuestionPrompter = Struct.new(:pastel, :questions, :notes, :name) do
        # Initially set to the defaults
        def answers
          @answers ||= questions.map { |q| [q.id, q.default] }.to_h
        end

        def summary
          SUMMARY.result self.binding
        end

        # Checks the questions dependencies and return if it should be prompted for
        def prompt?(question)
          return true unless question.related_question_id
          answers[question.related_question_id] == question.ask_when['eq']
        end

        # Ask all the questions in order
        def prompt_all
          questions.each do |question|
            prompt?(question) ? prompt_question(question) : skip_question(question)
          end
        end

        # Prompts the user for any answers they wish to change
        # return [Boolean] if the user requested questions to be re-asked
        def prompt_again
          opts = { default: 3, show_help: :always }
          choices = {
            'All' => :all, 'Selected' => :selected, 'Name Only' => :name, 'None' => :none
          }
          case prompt.select("Would you like to the script name or answers?", choices, **opts)
          when :all
            prompt_all
            prompt_notes
            true
          when :selected
            puts(pastel.yellow(<<~WARN).chomp) if dependencies?
              WARN: Some of the questions have dependencies on previous answers.
              The exact question prompts may differ if the dependencies change.
            WARN
            opts = { show_help: :always, echo: false, help: MULTI_HELP }
            selected = prompt.multi_select("Which questions would you like to change?", **opts) do |menu|
              questions.each do |question|
                next unless asked[question.id]
                menu.choice question.text, question
              end
              menu.choice 'Update notes about the script', :notes
            end
            ask_notes = selected.delete(:notes)
            prompt_questions(*selected) unless selected.empty?
            prompt_notes(false) if ask_notes
            true
          when :name
            prompt_name
            false
          else
            false
          end
        end

        def prompt_notes(confirm = true)
          if confirm
            open = prompt.yes?("Define notes about the script?", default: true)
          else
            prompt.keypress('Define notes about the script. Press any key to continue...')
            open = true
          end
          if open
            with_tmp_file do |file|
              file.write(notes)
              file.rewind
              editor.open(file.path)
              file.rewind
              self.notes = file.read
            end
          end
        end

        def prompt_name
          candidate = prompt.ask("What is the script's name?")
          script = Script.new(id: candidate)
          if script.valid?(:id_check)
            self.name = candidate
          elsif script.errors.any? { |e| e.type == :already_exists }
            $stderr.puts pastel.red(<<~ERROR.chomp)
              The selected name is already taken, please try again...
            ERROR
            prompt_name
          else
            # NOTE: Technically there maybe multiple errors, but the prompt is nicer
            # when only the first is emitted. This should be sufficient for must error conditions
            $stderr.puts pastel.red(<<~ERROR.chomp)
              The selected name is invalid as it #{script.errors.messages.first.last.first}
              Please try again...
            ERROR
            prompt_name
          end
        end

        private

        def prompt
          @prompt ||= TTY::Prompt.new(help_color: :yellow)
        end

        def editor
          @editor ||= Command.new_editor(pastel)
        end

        def prompt_questions(*selected_questions)
          id_map = selected_questions.map { |q| [q.id, true] }.to_h

          # NOTE: Loops through the original questions array to guarantee the order and allow dependencies
          questions.each do |question|
            # Check if a dependent question needs to be re-asked
            if question.related_question_id && id_map[question.related_question_id]
              prompt?(question) ? (id_map[question.id] = true) : skip_question(question)
            end

            # Skip questions that have not been flagged
            next unless id_map[question.id]

            # Warn the user a question is being skipped because the dependency is no longer met
            unless prompt?(question)
              $stderr.puts pastel.red.bold "Skipping the following question as the dependencies are no longer met:"
              $stderr.puts pastel.yellow question.text
              FlightJob.logger.error("Skipping selected question as the dependecies are no longer met: #{question.id}")
              id_map[question.id] = false
              skip_question(question)
              next
            end

            # Prompt for the answer
            original = answers[question.id]
            prompt_question(question)

            # Unset the flag if the answer hasn't changed
            # NOTE: This prevents dependent questions from being asked
            id_map[question.id] = false if original == answers[question.id]
          end
        end

        def prompt_question(question)
          asked[question.id] = true # Flags the question as asked
          answers[question.id] = case question.format['type']
          when 'text'
            prompt.ask(question.text, default: answers[question.id])
          when 'multiline_text'
            # NOTE: The 'default' field does not work particularly well for multiline inputs
            # Consider replacing with $EDITOR
            lines = prompt.multiline(question.text)
            lines.empty? ? answers[question.id] : lines.join('')
          when 'select'
            opts = { show_help: :always }
            choices = question.format['options'].each_with_index.map do |opt, idx|
              opts[:default] = idx + 1 if opt['value'] == answers[question.id]
              { name: opt['text'], value: opt['value'] }
            end
            prompt.select(question.text, choices, **opts)
          when 'multiselect'
            opts = { show_help: :always, echo: false, help: MULTI_HELP, default: [] }
            choices = question.format['options'].each_with_index.map do |opt, idx|
              opts[:default] << idx + 1 if answers[question.id].include?(opt['value'])
              { name: opt['text'], value: opt['value'] }
            end
            prompt.multi_select(question.text, choices, **opts)
          else
            raise InternalError, "Unexpectedly reached question type: #{question.format['type']}"
          end
        end

        # Tracks if a question has been asked
        def asked
          @asked ||= {}
        end

        # Checks if any of the questions have dependencies
        def dependencies?
          @dependencies ||= questions.any? { |q| q.related_question_id }
        end

        # Flags a question as being skipped
        # NOTE: The answer needs resetting in case it has been previously asked
        def skip_question(question)
          FlightJob.logger.debug("Skipping question: #{question.id}")
          asked[question.id] = false
          answers[question.id] = question.default
        end

        def with_tmp_file
          file = Tempfile.new('flight-job')
          yield(file) if block_given?
        ensure
          file.close
          file.unlink
        end
      end

      def run
        # Preliminarily check if the provided ID is okay
        verify_id(args[1]) if args.length > 1

        # Attempt to get the answers/notes from the input flags
        answers = answers_input
        notes = notes_input

        # Skip this section if both have been provided
        if answers && notes
          # NOOP

        # Handle STDIN contention (disables the prompts)
        elsif stdin_answers? || stdin_notes?
          raise InputError, <<~ERROR.chomp if answers.nil?
            Cannot prompt for the answers as standard input is in use!
            Please provide the answers with the following flag: #{pastel.yellow '--answers'}
          ERROR
          notes ||= ''

        # Prompt for this missing answers/notes
        elsif $stdout.tty?
          reask = true
          prompter = QuestionPrompter.new(pastel, template.generation_questions, notes || '')
          prompter.prompt_all if answers.nil?
          notes = prompter.prompt_notes if notes.nil?
          while reask
            puts "\n\n"
            pager.page prompter.summary
            reask = prompter.prompt_again
          end
          answers = prompter.answers
          notes = prompter.notes

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

        # Create the script object
        opts = ( args.length > 1 ? { id: args[1] } : {} )
        script = Script.new(
          template_id: template.id,
          script_name: template.script_template_name,
          answers: answers,
          notes: notes,
          **opts
        )

        # Save the script
        script.render_and_save

        # Render the script output
        puts Outputs::InfoScript.build_output(**output_options).render(script)
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

      def prompt
        @prompt = TTY::Prompt.new(help_color: :yellow)
      end

      def with_tmp_file
        file = Tempfile.new('flight-job')
        yield(file) if block_given?
      ensure
        file.close
        file.unlink
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

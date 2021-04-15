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
        <% questions.each do |question| -%>
        <% next unless asked[question.id] -%>
        <%= pastel.bold(question.text) %>
        <%
          value = answers[question.id]
          value = (value.is_a?(Array) ? value.join(',') : value.to_s)
        -%>
        <%= pastel.green value %>
        <% end -%>
      TEMPLATE

      # NOTE: The questions must be topologically sorted on their dependencies otherwise
      # these prompts will not function correctly
      QuestionPrompter = Struct.new(:prompt, :pastel, :questions) do
        # Initially set to the defaults
        def answers
          @answers ||= questions.map { |q| [q.id, q.default] }.to_h
        end

        def summary
          SUMMARY.result self.binding
        end

        # Tracks if a question has been asked
        def asked
          @asked ||= {}
        end

        # Checks if any of the questions have dependencies
        def dependencies?
          @dependencies ||= questions.any? { |q| q.related_question_id }
        end

        # Checks the questions dependencies and return if it should be prompted for
        def prompt?(question)
          return true unless question.related_question_id
          answers[question.related_question_id] == question.ask_when['eq']
        end

        # Flags a question as being skipped
        # NOTE: The answer needs resetting in case it has been previously asked
        def skip_question(question)
          FlightJob.logger.debug("Skipping question: #{question.id}")
          asked[question.id] = false
          answers[question.id] = question.default
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
          opts = { default: 'None', show_help: :always }
          case prompt.select("Would you like to change your answers?", ['All', 'Selected', 'None'], **opts)
          when 'All'
            prompt_all
            true
          when 'Selected'
            puts(pastel.yellow(<<~WARN).chomp) if dependencies?
              WARN: Some of the questions have dependencies on previous answers.
              The exact question prompts may differ if the dependencies change.
            WARN
            opts = { show_help: :always, echo: false, cycle: true, help: MULTI_HELP }
            selected = prompt.multi_select("Which questions would you like to change?", **opts) do |menu|
              questions.each do |question|
                next unless asked[question.id]
                menu.choice question.text, question
              end
            end
            prompt_questions(*selected)
            true
          else
            false
          end
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
      end

      def run
        # Resolves the answers
        answers = answers_input || begin
          if $stdout.tty? && stdin_notes?
            raise InputError, <<~ERROR.chomp
              Cannot prompt for the answers as standard input is in use!
              Please provide the answers with the following flag: #{pastel.yellow '--answers'}
            ERROR
          elsif $stdout.tty?
            prompter = QuestionPrompter.new(prompt, pastel, template.generation_questions)
            prompter.prompt_all
            reask = true
            while reask
              pager.page prompter.summary
              reask = prompter.prompt_again
            end
            prompter.answers
          else
            msg = <<~WARN.chomp
              No answers have been provided! Proceeding with the defaults.
            WARN
            $stderr.puts pastel.red(msg)
            FlightJob.logger.warn msg
            {}
          end
        end

        # Resolve the notes
        notes = notes_input || begin
          if $stdout.tty? && stdin_answers?
            FlightJob.logger.debug "Skipping notes prompt as STDIN is connected to the answers"
            ''
          elsif $stdout.tty? && prompt.yes?("Define notes about the script?", default: true)
            with_tmp_file do |file|
              new_editor.open(file.path)
              file.rewind
              file.read
            end
          else
            ''
          end
        end

        # Create the script object
        script = Script.new(
          template_id: template.id,
          script_name: template.script_template_name,
          answers: answers,
          notes: notes
        )

        # Apply the identity_name
        script.identity_name = args[1] if args.length > 1

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
    end
  end
end

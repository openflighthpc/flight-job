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

        <%= pastel.bold 'Name: ' -%><%= pastel.green(name) %>

        <%= pastel.bold 'Answers:' %>
        <%
            questions.each do |question|
              next unless prompt?(question) -%>
        <%
              if /[[:alnum:]]/.match?(question.text[-1])
                text = question.text
                delim = ':'
              else
                text = question.text[0..-2]
                delim = question.text[-1]
              end
        -%>
        <%=   pastel.blue.bold(text) -%><%= pastel.bold(delim) -%>
        <%    value = answers[question.id]
              value = question.default if value.nil?
              value = (value.is_a?(Array) ? value.join(',') : value.to_s)
              if value.empty?
        -%>
        <%=     " #{pastel.yellow('(none)')}" %>
        <%    elsif question.format['type'] == 'multiline_text' -%>

        <%      value.each_line do |line| -%>
        <%=       pastel.green(line.chomp) %>
        <%      end -%>
        <%    else -%>
        <%=     " #{pastel.green(value)}" %>
        <%    end -%>
        <%  end -%>

        <%= pastel.bold 'Notes:' %>
        <%  if notes.empty? -%>
        <%=   pastel.yellow('(none)') %>
        <%  else -%>
        <%    notes.each_line do |line| -%>
        <%=     pastel.green(line.chomp) %>
        <%    end -%>
        <%  end -%>
      TEMPLATE

      # NOTE: The questions must be topologically sorted on their dependencies otherwise
      # these prompts will not function correctly
      QuestionPrompter = Struct.new(:pastel, :pager, :questions, :notes, :name) do
        def initialize(*a)
          super
          if self.name
            @prompt_for_name = false
          else
            self.name ||= Script.new.id
            @prompt_for_name = true
          end
          @prompt_for_notes = true
        end

        def answers
          @answers ||= {}
        end

        def summary
          SUMMARY.result binding
        end

        # Checks the questions dependencies and return if it should be prompted for
        def prompt?(question)
          return true unless question.related_question_id
          answers[question.related_question_id] == question.ask_when['eq']
        end

        def prompt_loop
          reask = true
          while reask
            puts "\n"
            text = summary.sub(/\n+\Z/, '')
            diff = TTY::Screen.rows - text.lines.count
            # Work around issues with LESS -SFRX flag
            # The -F/--quit-if-one-screen flag disables less if the summary
            # fits on one page
            #
            # However, the prompt_again question adds an additional X lines,
            # which isn't being accounted for.
            #
            # The 'pager' should still be used, as the user may have changed
            # either PAGER/LESS env vars. Instead the text is padded with
            # newlines, if its length is X lines less than the terminal height
            if 0 < diff && diff < 7
              text = "#{text}#{"\n" * diff}"
            end
            pager.page text
            print "\n"
            reask = prompt_again
          end
        end

        # Ask all the questions in order
        def prompt_all
          questions.each do |question|
            prompt?(question) ? prompt_question(question) : skip_question(question)
          end
        end

        def open_notes
          @prompt_for_notes = false
          with_tmp_file do |file|
            file.write(notes)
            file.rewind
            editor.open(file.path)
            file.rewind
            self.notes = file.read
          end
        end

        # Used to prompt the user that the provided name is invalid
        # It is intended to be called up-front so it can unset default to the 'prompt_name' method
        def prompt_invalid_name
          return unless name
          script = Script.new(id: name)
          return if script.valid?(:id_check)
          error = script.errors.first
          msg = if error.type == :already_exists
                  'already exists!'
                else
                  "is invalid as it #{error.message}"
                end
          prompt.keypress(pastel.red.bold <<~WARN.chomp)
            The provided script name #{msg}
            You will need to provide a new name. Press any key to continue...
          WARN
          @prompt_for_name = true
          self.name = Script.new.id
        end

        def prompt_name
          opts = name ? { default: name } : { required: true }
          candidate = prompt.ask("What is the script's identifier?", **opts)
          script = Script.new(id: candidate)
          if script.valid?(:id_check)
            @prompt_for_name = false
            self.name = candidate
          elsif script.errors.any? { |e| e.type == :already_exists }
            $stderr.puts pastel.red(<<~ERROR.chomp)
              The selected identifier is already taken, please try again...
            ERROR
            prompt_name
          else
            # NOTE: Technically there maybe multiple errors, but the prompt is nicer
            # when only the first is emitted. This should be sufficient for must error conditions
            $stderr.puts pastel.red(<<~ERROR.chomp)
              The selected identifier is invalid as it #{script.errors.first.message}
              Please try again...
            ERROR
            prompt_name
          end
        end

        private

        # Prompts the user for any answers they wish to change
        # return [Boolean] if the user requested questions to be re-asked
        def prompt_again
          opts = {
            default: if @prompt_for_selected
                       @prompt_for_selected = false
                       3
                     elsif @prompt_for_name
                       1
                     elsif @prompt_for_notes
                       2
                     else
                       5
                     end,
            show_help: :always }
          choices = {
            'Change the script identifier.' => :name,
            "#{notes.empty? ? 'Add' : 'Edit the'} notes about the script." => :notes,
            'Change the answers to selected questions.' => :selected,
            'Re-ask all the questions.' => :all,
            'Save and quit!' => :finish
          }
          case prompt.select("What would you like to do next?", choices, **opts)
          when :all
            prompt_all
            true
          when :selected
            puts(pastel.yellow(<<~WARN).chomp) if dependencies?
              WARN: Some of the questions have dependencies on previous answers.
              The exact question prompts may differ if the dependencies change.
            WARN
            opts = { show_help: :always, echo: false, help: MULTI_HELP }
            text = "Which questions would you like to change?"
            selected = prompt.multi_select(text, **opts) do |menu|
              questions.each do |question|
                next unless prompt?(question)
                menu.choice question.text, question
              end
            end
            if selected.empty?
              @prompt_for_selected = true
              prompt.keypress(pastel.yellow(<<~WARN.chomp))

                You have not selected any questions to be re-ask!
                Questions need to be explicitly selected with Space.

                Press any key to continue...
              WARN
            else
              prompt_questions(*selected)
            end
            true
          when :name
            prompt_name
            true
          when :notes
            open_notes
          else
            false
          end
        end

        # Checks if the notes have been defined
        def notes?
          !notes.to_s.empty?
        end

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
          default = answers.key?(question.id) ? answers[question.id] : question.default
          value = case question.format['type']
          when 'text'
            prompt.ask(question.text, default: default)
          when 'multiline_text'
            # NOTE: The 'default' field does not work particularly well for multiline inputs
            # Consider replacing with $EDITOR
            lines = prompt.multiline(question.text)
            lines.empty? ? answers[question.id] : lines.join('')
          when 'select'
            opts = { show_help: :always }
            choices = question.format['options'].each_with_index.map do |opt, idx|
              opts[:default] = idx + 1 if opt['value'] == default
              { name: opt['text'], value: opt['value'] }
            end
            prompt.select(question.text, choices, **opts)
          when 'multiselect'
            opts = { show_help: :always, echo: false, help: MULTI_HELP, default: [] }
            choices = question.format['options'].each_with_index.map do |opt, idx|
              opts[:default] << idx + 1 if default.is_a?(Array) && default.include?(opt['value'])
              { name: opt['text'], value: opt['value'] }
            end
            prompt.multi_select(question.text, choices, **opts)
          when 'time'
            prompt.ask(question.text) do |q|
              q.default default
              q.validate(/\A24:00|([0-1]\d|2[0-3]):[0-5]\d\Z/, "Times must be in HH:MM format")
            end
          when 'number'
            # NOTE: The 'number' input has parity with HTML <input type="number"/>
            # By default, this only allows integers. This behaviour has been replicated here
            #
            # Consider refactoring to allow floating points
            prompt.ask(question.text, convert: :integer, default: default)
          else
            raise InternalError, "Unexpectedly reached question type: #{question.format['type']}"
          end

          # Validate the response
          errors = question.validate_value(value)
          if errors.empty?
            answers[question.id] = value

          elsif msg = errors.find { |t, _| t == :type }
            # NOTE: There are a couple of ways this edge condition can be triggered
            # Ideally the template validation would prevent them, however this introduces
            # complexity to the validation.
            #
            # Consider implementing full validation
            FlightJob.logger.error <<~ERROR.chomp
              Recieved the following unexpected error when asking question '#{question.id}':
               * #{msg.last}
            ERROR
            FlightJob.logger.error <<~ERROR.squish
              This is most likely because of a mismatch between the 'format'/'options'
              keys and the 'validate' specification. The template needs updating to be
              consistent.
            ERROR
            raise InternalError, <<~ERROR.chomp
              Failed to coerce the anwer to '#{question.id}'!
              Pleasse contact your system administrator for further assistance.
            ERROR
          else
            $stderr.puts pastel.red.bold "The given value is invalid as it:"
            errors.each do |_, msg|
              first, rest = msg.split("\n", 2)
              lines = rest.to_s.chomp.split("\n").map { |l| "   #{l}" }.join("\n")
              $stderr.puts pastel.red " * #{first}#{ "\n" + lines unless lines.empty? }"
            end
            $stderr.puts pastel.yellow "Please try again..."
            prompt_question(question)
          end
        end

        # Checks if any of the questions have dependencies
        def dependencies?
          @dependencies ||= questions.any? { |q| q.related_question_id }
        end

        # Flags a question as being skipped and removes the previous answer
        def skip_question(question)
          FlightJob.logger.debug("Skipping question: #{question.id}")
          answers.delete(question.id)
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

        # Create the script object
        opts = ( name ? { id: name } : {} )
        script = Script.new(
          template_id: template.id,
          script_name: template.script_template_name,
          answers: answers,
          notes: notes,
          **opts
        )

        script.tags = template.tags

        # Save the script
        script.render_and_save

        # Return the script
        script
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

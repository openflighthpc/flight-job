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

require 'tty-prompt'
require 'tempfile'

module FlightJob
  # Prompt the user for answers to the given questions.
  #
  # When the user has answered the questions they are shown a summary and
  # given a chance to accept or go round again.
  #
  # NOTE: The questions must be topologically sorted on their dependencies
  # otherwise these prompts will not function correctly
  QuestionPrompter = Struct.new(:pastel, :pager, :questions, :notes, :id) do
    MULTI_HELP = "(Press ↑/↓/←/→ arrow to scroll, Space/Ctrl+A|R to select (all|rev) and Enter to finish)"

    SUMMARY = ERB.new(<<~'TEMPLATE', nil, '-')
      <%= pastel.bold.underline 'SUMMARY' %>

      <%= pastel.bold 'ID: ' -%><%= pastel.green(id) %>

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

    def initialize(*a)
      super
      if self.id
        @prompt_for_id = false
      else
        self.id ||= Script.new.id
        @prompt_for_id = true
      end
      @prompt_for_notes = true
    end

    def answers
      @answers ||= {}
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

    # Warn user that the provided id is invalid.
    #
    # It is intended to be called up-front so it can unset default to the
    # 'prompt_id' method.
    def prompt_invalid_id
      return unless id
      script = Script.new(id: id)
      return if script.valid?(:id_check)
      error = script.errors.first
      msg = if error.type == :already_exists
              'already exists!'
            else
              "is invalid as it #{error.message}"
            end
      prompt.keypress(pastel.red.bold <<~WARN.chomp)
        The provided script id #{msg}
        You will need to provide a new id. Press any key to continue...
      WARN
      @prompt_for_id = true
      self.id = Script.new.id
    end

    private

    def prompt_id
      opts = id ? { default: id } : { required: true }
      candidate = prompt.ask("What is the script's identifier?", **opts)
      script = Script.new(id: candidate)
      if script.valid?(:id_check)
        @prompt_for_id = false
        self.id = candidate
      elsif script.errors.any? { |e| e.type == :already_exists }
        $stderr.puts pastel.red(<<~ERROR.chomp)
          The selected identifier is already taken, please try again...
        ERROR
        prompt_id
      else
        # NOTE: Technically there maybe multiple errors, but the prompt is nicer
        # when only the first is emitted. This should be sufficient for must error conditions
        $stderr.puts pastel.red(<<~ERROR.chomp)
          The selected identifier is invalid as it #{script.errors.first.message}
          Please try again...
        ERROR
        prompt_id
      end
    end

    # Return true if the question should be asked of the user.
    def prompt?(question)
      return true unless question.related_question_id
      answers[question.related_question_id] == question.ask_when['eq']
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

    def summary
      SUMMARY.result binding
    end

    # Prompts the user for any answers they wish to change
    # return [Boolean] if the user requested questions to be re-asked
    def prompt_again
      opts = {
        default: if @prompt_for_selected
                   @prompt_for_selected = false
                   3
                 elsif @prompt_for_id
                   1
                 elsif @prompt_for_notes
                   2
                 else
                   5
                 end,
        show_help: :always }
      choices = {
        'Change the script identifier.' => :id,
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
        # XXX Keep or remove???
        # puts(pastel.yellow(<<~WARN).chomp) if dependencies?
        #   WARN: Some of the questions have dependencies on previous answers.
        #   The exact question prompts may differ if the dependencies change.
        # WARN
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
      when :id
        prompt_id
        true
      when :notes
        open_notes
      else
        false
      end
    end

    def prompt
      @prompt ||= TTY::Prompt.new(help_color: :yellow)
    end

    def editor
      @editor ||= Command.new_editor(pastel)
    end

    def prompt_questions(*selected_questions)
      id_map = selected_questions.map { |q| [q.id, true] }.to_h

      # NOTE: Loops through the original questions array to guarantee the
      # order and allow dependencies
      questions.each do |question|
        # Check if a dependent question needs to be re-asked
        if question.related_question_id && id_map[question.related_question_id]
          prompt?(question) ? (id_map[question.id] = true) : skip_question(question)
        end

        # Skip questions that have not been flagged
        next unless id_map[question.id]

        # Warn the user a question is being skipped because the dependency is
        # no longer met
        unless prompt?(question)
          $stderr.puts pastel.red.bold "Skipping the following question as the dependencies are no longer met:"
          $stderr.puts pastel.yellow question.text
          FlightJob.logger.debug("Skipping selected question as the dependecies are no longer met: #{question.id}")
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
      answers[question.id] =
        case question.format['type']
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
        else
          raise InternalError, "Unexpectedly reached question type: #{question.format['type']}"
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
end

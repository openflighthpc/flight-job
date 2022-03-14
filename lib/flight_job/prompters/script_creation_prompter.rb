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
  module Prompters

    # Used for interactive creation of scripts.
    #
    # It prompts the user for:
    #
    # 1. Answers to the given questions.
    # 2. An identifier for the script
    # 3. Notes for the script.
    #
    # NOTE: The questions must be topologically sorted on their dependencies
    # otherwise these prompts will not function correctly
    class ScriptCreationPrompter < BasePrompter
      SUMMARY = ERB.new(<<~'TEMPLATE', nil, '-')
        <%= pastel.bold.underline 'SUMMARY' %>

        <%= pastel.bold 'ID: ' -%><%= pastel.green(id) %>

        <%= pastel.bold 'Answers:' %>
        <%
            questions.each do |question|
              next unless prompt?(question) -%>
        <%=   question_label(question) -%>
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

      attr_accessor :id, :answers, :notes

      def initialize(pastel, pager, questions, answers, id, notes)
        super(pastel, pager, questions, answers)
        @notes = notes
        @id = id
        if @id
          @prompt_for_id = false
        else
          @id ||= Script.new.id
          @prompt_for_id = true
        end
        @prompt_for_notes = true
      end

      def call
        prompt_invalid_id
        super
      end

      private

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
        @id = Script.new.id
      end

      def prompt_id
        opts = id ? { default: id } : { required: true }
        candidate = prompt.ask("\nWhat is the script's identifier?", **opts)
        script = Script.new(id: candidate)
        if script.valid?(:id_check)
          @prompt_for_id = false
          @id = candidate
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
          opts = { show_help: :always, echo: false, help: MULTI_HELP }
          text = "\nWhich questions would you like to change?"
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

      def editor
        @editor ||= Command.new_editor(pastel)
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

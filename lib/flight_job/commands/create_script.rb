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
      SUMMARY = ERB.new(<<~'TEMPLATE', nil, '-')
        <%= pastel.bold.underline 'SUMMARY' %>
        <% questions.each do |question| -%>
        <%= pastel.bold(question.text) %>
        <%
          value = answers[question.id]
          value = (value.is_a?(Array) ? value.join(',') : value.to_s)
        -%>
        <%= pastel.green value %>
        <% end -%>
      TEMPLATE

      QuestionPrompter = Struct.new(:prompt, :pastel, :questions) do
        # Initially set to the defaults
        def answers
          @answers ||= questions.map { |q| [q.id, q.default] }.to_h
        end

        # Allows lookups by question ID
        def questions_map
          @questions_map ||= questions.map { |q| [q.id, q] }.to_h
        end

        def summary
          SUMMARY.result self.binding
        end

        def prompt_all
          questions.each do |question|
            if question.related_question_id
              related = answers[question.related_question_id]
              unless related == question.ask_when['eq']
                FlightJob.logger.debug("Skipping question: #{question.id}")
                next
              end
            end

            prompt_id(question.id)
          end
        end

        def prompt_id(question_id)
          question = questions_map[question_id]
          answers[question_id] = case question.format['type']
          when 'text'
            prompt.ask(question.text, default: question.default)
          when 'multiline_text'
            # NOTE: The 'default' field does not work particularly well for multiline inputs
            # Consider replacing with $EDITOR
            lines = prompt.multiline(question.text)
            lines.empty? ? question.default : lines.join('')
          when 'select'
            opts = { show_help: :always }
            choices = question.format['options'].each_with_index.map do |opt, idx|
              opts[:default] = idx + 1 if opt['value'] == question.default
              { name: opt['text'], value: opt['value'] }
            end
            prompt.select(question.text, choices, **opts)
          when 'multiselect'
            opts = { show_help: :always}
            choices = question.format['options'].each_with_index.map do |opt, idx|
              opts[:default] = idx + 1 if question.default.include?(opt['value'])
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
            pager.page prompter.summary
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

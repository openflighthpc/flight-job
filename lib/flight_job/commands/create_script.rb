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

module FlightJob
  module Commands
    class CreateScript < Command
      # TODO: Make me configurable
      MAX_STDIN_SIZE = 1*1024*1024

      def run
        answers = answers_input || prompt_answers

        # Render the script
        script = Script.new(
          template_id: template.id,
          answers: answers,
          notes: notes_input
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

      def answers_input
        return unless opts.stdin || opts.answers
        string = if opts.stdin || opts.answers == '@-'
                   cached_stdin
                 elsif opts.answers[0] == '@'
                   read_file(opts.answers[1..])
                 else
                   opts.answers
                 end
        JSON.parse(string)
      rescue JSON::ParserError
        flag = opts.stdin ? '--stdin' : '--answers'
        raise InputError, "The following input is not valid JSON: #{pastel.yellow flag}"
      end

      def notes_input
        return unless opts.notes
        if opts.notes == '@-'
          cached_stdin
        elsif opts.notes[0] == '@'
          read_file(opts.notes[1..])
        else
          opts.notes
        end
      end

      # TODO: Error if not connected to a TTY
      def prompt_answers
        template.generation_questions.each_with_object({}) do |question, memo|
          if question.related_question_id
            related = memo[question.related_question_id]
            unless related == question.ask_when['eq']
              FlightJob.logger.debug("Skipping question: #{question.id}")
              next
            end
          end

          memo[question.id] = case question.format['type']
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

      def prompt
        @prompt = TTY::Prompt.new(help_color: :yellow)
      end

      # Technically multiple flags may try and read STDIN. Whilst this would be an "unusual"
      # use case, it is still "technically" valid. In this case STDIN becomes the input for
      # both flags. However as the input can only be read once, it needs to be cached
      def cached_stdin
        @cached_stdin ||= $stdin.read_nonblock(MAX_STDIN_SIZE).tap do |str|
          if str.length == MAX_STDIN_SIZE
            raise InputError, "The STDIN exceeds the maximum size of: #{MAX_STDIN_SIZE}B"
          end
        end
      rescue Errno::EWOULDBLOCK, Errno::EWOULDBLOCK
        raise InputError, "Failed to read the data from STDIN"
      end

      def read_file(path)
        if File.exists?(path)
          File.read(path)
        else
          raise InputError, "Could not locate file: #{path}"
        end
      end
    end
  end
end

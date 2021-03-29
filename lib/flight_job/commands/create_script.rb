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
      MAX_STDIN_SIZE = 1*1024*1024

      def run
        if args.length > 1
          if args[1].length > FlightJob.config.maximum_id_length
            raise InputError,
              "The id '#{args[1]}' exceeds the maximum length of #{FlightJob.config.maximum_id_length}"
          end
          unless Script::ID_REGEX.match?(args[1])
            raise InputError, "The new id '#{args[1]}' is invalid. It must be alphanumeric but may include dot, hyphen, and underscore: -_."
          end
        end

        # Attempt to reserve the user's ID
        script_opts = {
          template_id: template.id,
          script_name: template.script_template_name
        }.tap { |o| o[:reserve_id] = args[1] if args.length > 1 }
        script = Script.new(**script_opts)

        if script.exists?
          # Ensure the script does not already exist
          raise DuplicateError, "The script '#{script.public_id}' already exists!"
        elsif ! script.reserved?
          # NOTE: This prevents race conditions in the create and *should* be
          # a temporary condition
          raise InternalError, <<~ERROR
            Unexpectedly failed to create '#{script.public_id}', please try again.
            If this error persists, please contact your system administrator.
          ERROR
        end

        # Cleanup the directory if required (leaving the reservation)
        files = Dir.glob(File.join(File.dirname(script.metadata_path), '*'))
        files.delete script.reservation_path
        unless files.empty?
          msg = <<~WARN.chomp
            Removing stale file(s):
            #{files.join("\n")}
          WARN
          $stderr.puts pastel.red(msg)
          FlightJob.logger.warn(msg)
        end
        files.each { |f| FileUtils.rm_f f }

        answers = opts.stdin ? stdin_answers : prompt_answers

        # Render the script
        script.render_and_save(**answers)

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

      def stdin_answers
        # TODO: Validate the correct answers have been provided
        input = $stdin.read_nonblock(MAX_STDIN_SIZE)
        if input.length == MAX_STDIN_SIZE
          raise InputError, "The STDIN exceeds the maximum size of: #{MAX_STDIN_SIZE}B"
        end
        JSON.parse(input)
      rescue Errno::EWOULDBLOCK, Errno::EWOULDBLOCK
        raise InputError, "Failed to read the data from STDIN"
      rescue JSON::ParserError
        raise InputError, 'The STDIN is not valid JSON!'
      end

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
    end
  end
end

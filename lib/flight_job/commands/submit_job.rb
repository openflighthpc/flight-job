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

require_relative "../prompters/submission_prompter"

module FlightJob
  module Commands
    class SubmitJob < Command
      VALIDATION_ERROR = ERB.new(<<~'TEMPLATE', nil, '-')
        Cannot continue as the following errors occurred whilst validating the answers
        <% errors.each do |key, msgs| -%>
        <%   next if msgs.empty? -%>

        <%= key == :root ? "The root value" : "'" + key + "'" -%> is invalid as it:
        <%   msgs.each do |msg| -%>
        <%= ::FlightJob::Prompters::SubmissionPrompter.bulletify(msg) %>
        <%   end -%>
        <% end -%>
      TEMPLATE

      def run
        # The answers can be provided in a number of different ways.
        #
        # 1. The answers can be given on the command line.  Either inline or
        #    as a file to read from.  That file could be `/dev/stdin`.
        # 2. The user can be interactively prompted for them.  This requires
        #    stdin to not already be used and for stdout to be a TTY.
        # 3. The defaults can be used.
        #
        # The branches below cover all of these cases.

        job =
          if answers_provided?
            # Answers have been provided either via command line argument or
            # read from stdin.  There is nothing to prompt for.
            create_job(answers)

          elsif $stdout.tty?
            # We're missing the answers.  Stdin is not used and stdout is a
            # TTY, so we can prompt for what's missing.
            run_prompter(answers)

          else
            # We don't have the answers.  We use the (hopefully) sensible
            # defaults if they are missing.
            msg = "No answers have been provided. Proceeding with the defaults."
            $stderr.puts pastel.red(msg)
            FlightJob.logger.warn msg
            create_job(answers)
          end

        job.submit
        puts render_output(Outputs::InfoJob, job.decorate)
      end

      private

      def run_prompter(answers)
        prompter = Prompters::SubmissionPrompter.new(
          pastel,
          pager,
          questions,
          answers,
        )
        prompter.call
        create_job(prompter.answers)
      end

      def create_job(answers)
        job = Job.new(id: job_id)
        job.initialize_metadata(script, answers)
        job
      end

      def script
        @script ||= load_script(args.first)
      end

      def job_id
        NameGenerator.new_job(script.id).next_name
      end

      def answers_provided?
        !answers.nil?
      end

      def answers_provided_on_stdin?
        if opts.stdin
          true
        elsif opts.answers
          stdin_flag?(opts.answers)
        else
          false
        end
      end

      def answers
        return unless opts.stdin || opts.answers
        string = if answers_provided_on_stdin?
                   cached_stdin
                 elsif opts.answers[0] == '@'
                   read_file(opts.answers[1..])
                 else
                   opts.answers
                 end
        JSON.parse(string).tap do |hash|
          # Inject the defaults if possible
          if hash.is_a?(Hash)
            questions.each do |question|
              next if question.default.nil?
              next if hash.key? question.id
              hash[question.id] = question.default
            end
          end

          # Validate the answers
          errors = validate_answers(hash)
          next if errors.all? { |_, msgs| msgs.empty? }

          # Raise the validation error
          bind = OpenStruct.new(errors).instance_exec { binding }
          msg = VALIDATION_ERROR.result(bind)
          raise InputError, msg.chomp
        end
      rescue JSON::ParserError
        raise InputError, <<~ERROR.chomp
          Failed to parse the answers as they are not valid JSON:
          #{$!.message}
        ERROR
      end

      def template
        @_template ||= script.load_template
      end

      def questions
        template.submission_questions
      end

      def validate_answers(hash)
        template.validate_submission_questions_values(hash)
      end
    end
  end
end

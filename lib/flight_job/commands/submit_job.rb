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

require_relative "concerns/answers_options_concern"

module FlightJob
  module Commands
    class SubmitJob < Command
      include Concerns::AnswersOptionsConcern

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

        submit(job)
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

      def submit(job)
        if submit_job_via_desktop_session?(job)
          submit_job_via_desktop_session(job)
        else
          # Submit the job via sbatch.
          job.submit
        end
      end

      def script
        @_script ||= load_script(args.first)
      end

      def job_id
        NameGenerator.new_job(script.id).next_name
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

      def submit_job_via_desktop_session?(job)
        tags = script.tags
        tags.include?('script:type=interactive') && tags.include?('session:order=desktop:alloc')
      end

      def submit_job_via_desktop_session(job)
        # XXX This contains much duplicated code with
        # JobTransitions::Submitter.  When the JobTransitions are reworked, we
        # should look at a better abstraction than this.
        job.save
        script_path = job.metadata["rendered_path"]
        FileUtils.cp(script.script_path, script_path)
        submit_args = script.generate_submit_args(job)
        script_command = [
          script_path,
          *submit_args.scheduler_args,
          "--",
          *submit_args.job_script_args,
        ]

        env = {
          'CONTROLS_DIR' => job.controls_dir.path,
          'FLIGHT_JOB_ID' => job.id,
          'FLIGHT_JOB_NAME' => job.name,
        }
        result = FlightJob::DesktopCLI.start_session(
          env: env,
          script: script_command.join(" "),
        )
        if result.success?
          job.desktop_id = result.desktop_id
        else
          job.metadata['job_type'] = 'FAILED_SUBMISSION'
          job.save
        end
      end
    end
  end
end

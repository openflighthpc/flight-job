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
        if script.tags.include?('script:type=interactive') && script.tags.include?('session:host=login')
          # XXX Submit the job via flight desktop.
          # 
          # We have this job, what we need to do is:
          #
          # 1. Run `flight desktop start ... --script ...`
          # 2. Collect data from the `srun` command.
          # 3. Update this job's metadata from the `srun` command somehow.
          #
          # Want to be able to
          #
          # 1. View the job.
          # 2. Have the job linked to the desktop session.
          # 3. Be able to cancel the job.
          # 4. Have the job updated.
          #
          # SOLUTION:
          #
          # 1. Port subprocess, et al to Flight Job.
          # 2. Implement a DesktopCLI class.
          # 3. Process srun to save job id when queued.
          #    /opt/flight/opt/slurm/bin/srun --pty /bin/bash 2> >( tee >( sed 's/.*srun : job \([0-9]*\).*/\1/' > /tmp/queued  ) )
          # 4. Have the job script write out its SLURM_JOB_ID and its job_type
          #    (SINGLETON).
          # 5. We can then monitor the process.

          job.save_metadata
          FileUtils.touch(job.active_index_path)
          script_path = job.metadata["rendered_path"]
          FileUtils.cp(script.script_path, script_path)
          submit_args = script.generate_submit_args(job)
          # script_command = [script_path, *submit_args.scheduler_args]
          script_command = [
            script_path,
            *submit_args.scheduler_args,
          ]

          env = {
            'CONTROLS_DIR' => job.controls_dir.path,
          }
          result = FlightJob::DesktopCLI.start_session(
            env: env,
            script: script_command.join(" "),
          )
          if result.success?
            job.desktop_id = result.desktop_id
          end
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
    end
  end
end

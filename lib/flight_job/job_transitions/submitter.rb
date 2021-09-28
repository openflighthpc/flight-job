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

module FlightJob
  module JobTransitions
    Submitter = Struct.new(:job) do
      include JobTransitionHelper
      include ActiveModel::Validations

      validate do
        job.valid?
        job.errors.each { |e| @errors << e }
      end

      validate do
        unless job.load_script.valid?(:load)
          job.errors.add(:script, 'is missing or invalid')
        end
      end

      def run
        run!
        return true
      rescue
        Flight.logger.error "Failed to submit job '#{job.id}'"
        Flight.logger.warn $!
        return false
      end

      def run!
        # Validate and load the script
        unless job.valid?
          Flight.logger.error("The job is not in a valid submission state: #{job.id}\n") do
            job.errors.full_messages.join("\n")
          end
          raise InternalError, 'Unexpectedly failed to submit the job'
        end
        script = job.load_script

        # Write the initial metadata
        job.save_metadata
        FileUtils.touch job.active_index_path

        # Duplicate the script into the job's directory
        FileUtils.cp script.script_path, job.metadata["rendered_path"]

        # Run the submission command
        FlightJob.logger.info("Submitting Job: #{job.id}")
        cmd = [FlightJob.config.submit_script_path, job.metadata["rendered_path"]]
        execute_command(*cmd, tag: 'submit') do |status, out, err, data|
          # set the status/stdout/stderr
          job.metadata['submit_status'] = status.exitstatus
          job.metadata['submit_stdout'] = out
          job.metadata['submit_stderr'] = err

          # Return early if the submission failed
          unless status.success?
            job.metadata['job_type'] = 'FAILED_SUBMISSION'
            job.save_metadata
            FileUtils.rm_f job.active_index_path
            return
          end

          # Save the job into the monitoring state
          metadata["job_type"] = "MONITORING"
          save_metadata

          # Bootstrap the monitors
          BootstrapMonitor.new(job).run!
        end
      end
    end
  end
end

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
    class SubmitTransition < SimpleDelegator
      include JobTransitionHelper
      include ActiveModel::Validations

      SUBMIT_RESPONSE_SCHEMA = JSONSchemer.schema({
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["id", "results_dir"],
        "properties" => {
          "id" => { "type" => "string" },
          "stdout" => { "type" => ["string", "null"] },
          "stderr" => { "type" => ["string", "null"] },
          "results_dir" => { "type" => "string" },
        }
      })

      validate do
        __getobj__.valid?
        __getobj__.errors.each { |e| @errors << e }
      end

      validate do
        if submitted?
          errors.add(:submitted, 'the job has already been submitted')
        end
        unless load_script.valid?(:load)
          errors.add(:script, 'is missing or invalid')
        end
      end

      def run!
        raise NotImplementedError
      end

      def run!
        # Validate and load the script
        unless valid?
          FlightJob.config.logger("The script is not in a valid submission state: #{id}\n") do
            errors.full_messages
          end
          raise InternalError, 'Unexpectedly failed to submit the job'
        end
        script = load_script

        # Generate the initial metadata path file
        FileUtils.mkdir_p File.dirname(initial_metadata_path)
        File.write initial_metadata_path, YAML.dump(active_metadata)

        # Duplicate the script into the job's directory
        # NOTE: Eventually this should probably be named after the job_name question
        metadata["rendered_path"] = File.join(job_dir, script.script_name)
        FileUtils.cp script.script_path, metadata["rendered_path"]

        # Run the submission command
        FlightJob.logger.info("Submitting Job: #{id}")
        cmd = [FlightJob.config.submit_script_path, metadata["rendered_path"]]
        execute_command(*cmd, tag: 'submit') do |status, out, err, data|
          # set the status/stdout/stderr
          metadata['submit_status'] = status.exitstatus
          metadata['submit_stdout'] = out
          metadata['submit_stderr'] = err

          # Set the initial state based on the exit status
          if metadata['submit_status'] == 0
            metadata['state'] = 'PENDING'
          else
            metadata['state'] = 'FAILED'
          end

          # Persist the current state of the job
          FileUtils.mkdir_p File.dirname(metadata_path)
          File.write metadata_path, YAML.dump(metadata)

          # Parse stdout on successful commands
          if status.success?
            validate_data(SUBMIT_RESPONSE_SCHEMA, data, tag: 'submit')
            metadata['scheduler_id'] = data['id']
            metadata['stdout_path'] = data['stdout'].blank? ? nil : data['stdout']
            metadata['stderr_path'] = data['stderr'].blank? ? nil : data['stderr']
            metadata['results_dir'] = data['results_dir']
          end

          # Persist the updated version of the metadata
          File.write(metadata_path, YAML.dump(metadata))

          # Create the indexing file if in non-terminal state
          unless Job.terminal?
            FileUtils.touch active_index_path
          end
        end
      end
    end
  end
end

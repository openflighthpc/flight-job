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

      SHARED_KEYS = ["job_type", "version", "id", "results_dir"]
      SHARED_PROPS = {
        "version" => { "const" => 1 },
        "id" => { "type" => "string", "minLength" => 1 },
        "results_dir" => { "type" => "string", "minLength" => 1 }
      }
      SCHEMAS = {
        initial:  JSONSchemer.schema({
          "type" => "object",
          "additionalProperties" => true,
          "required" => SHARED_KEYS,
          "properties" => {
            **SHARED_PROPS,
            "job_type" => { "enum" => ["SINGLETON", "ARRAY"] }
          }
        }),

        'SINGLETON' => JSONSchemer.schema({
          "type" => "object",
          "additionalProperties" => false,
          "required" => [*SHARED_KEYS, "stdout", "stderr", "results_dir"],
          "properties" => {
            **SHARED_PROPS,
            "job_type" => { "const" => "SINGLETON" },
            "stdout" => { "type" => "string", "minLength" => 1 },
            "stderr" => { "type" => "string", "minLength" => 1 }
          }
        }),

        "ARRAY" => JSONSchemer.schema({
          "type" => "object",
          "additionalProperties" => false,
          "required" => [*SHARED_KEYS, "lazy"],
          "properties" => {
            **SHARED_PROPS,
            "job_type" => { "const" => "ARRAY" },
            "lazy" => { "const" => true }
          }
        })
      }

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

        # Write the initial metadata
        save_metadata
        FileUtils.touch active_index_path

        # Duplicate the script into the job's directory
        FileUtils.cp script.script_path, metadata["rendered_path"]

        # Run the submission command
        FlightJob.logger.info("Submitting Job: #{id}")
        cmd = [FlightJob.config.submit_script_path, metadata["rendered_path"]]
        execute_command(*cmd, tag: 'submit') do |status, out, err, data|
          # set the status/stdout/stderr
          metadata['submit_status'] = status.exitstatus
          metadata['submit_stdout'] = out
          metadata['submit_stderr'] = err

          # Return early if the submission failed
          unless status.success?
            metadata['job_type'] = 'FAILED_SUBMISSION'
            FileUtils.rm_f active_index_path
            return
          end

          # Validate the payload format
          begin
            validate_data(SCHEMAS[:initial], data, tag: 'submit (initial)')
            type = data['job_type']
            validate_data(SCHEMAS[type], data, tag: "submit (#{type})")
          rescue CommandError
            # The command lied about exiting 0! It did not report the json payload
            # correctly. Changing the status to 126
            metadata['job_type'] = 'FAILED_SUBMISSION'
            metadata['submit_status'] = 126
            metadata["submit_stderr"] << "\nFailed to parse JSON response"
            save_metadata
            raise $!
          end

          # The job was submitted correctly and is now pending
          case data['job_type']
          when 'SINGLETON'
            metadata['job_type'] = 'SINGLETON'
            metadata['state'] = 'PENDING'
            metadata['scheduler_id'] = data['id']
            metadata['stdout_path'] = data['stdout']
            metadata['stderr_path'] = data['stderr']
            metadata['results_dir'] = data['results_dir']
            save_metadata
          end

          # Remove the indexing file if in non-terminal state
          if terminal?
            FileUtils.rm_f active_index_path
          end
        end
      end
    end
  end
end

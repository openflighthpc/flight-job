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
    class FailedSubmissionTransition < SimpleDelegator
      ACTIVE_SCHEMA = JSONSchemer.schema({
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["script_id", "created_at"],
        "properties" => {
          "script_id" => { "type" => "string" },
          "created_at" => { "type" => "string", "format" => "date-time" },
        }
      })

      def run
        # Remove the initial_metadata_path if metadata_path exists
        FileUtils.rm_f initial_metadata_path if File.exists? metadata_path
        return unless File.exists? initial_metadata_path

        schema_errors = ACTIVE_SCHEMA.validate(active_metadata).to_a
        if schema_errors.empty?
          # Check if the maximum pending submission time has elapsed
          start = DateTime.rfc3339(created_at).to_time.to_i
          now = Time.now.to_i
          if now - start > FlightJob.config.submission_period
            FlightJob.logger.error <<~ERROR
              The following job is being flaged as FAILED as it has not been submitted: #{id}
            ERROR
            metadata['state'] = 'FAILED'
            metadata['submit_status'] = 126
            metadata['submit_stdout'] = ''
            metadata['submit_stderr'] = 'Failed to run the submission command for an unknown reason'
            FileUtils.mkdir_p File.dirname(metadata_path)
            File.write metadata_path, YAML.dump(metadata)
            FileUtils.rm_f initial_metadata_path
          else
            FlightJob.logger.info "Ignoring the following job as it is pending submission: #{id}"
          end
        else
          FlightJob.logger.error <<~ERROR.chomp
            The following active file is invalid: #{initial_metadata_path}
          ERROR
          FileUtils.rm_f initial_metadata_path
        end
      end
    end
  end
end

#==============================================================================
# Copyright (C) 2022-present Alces Flight Ltd.
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

require_relative "../metadata_base"
require_relative "validator"

module FlightJob
  class Job
    class Metadata < MetadataBase

      RAW_SCHEMA = JSON.parse File.read(Flight.config.job_schema_path)
      SCHEMA_VERSION = RAW_SCHEMA['oneOf'][0]["properties"]['version']['const']
      # Break up the raw schema into its components
      # This makes slightly nicer error reporting by removing the oneOf
      SCHEMAS = {
        common: JSONSchemer.schema(RAW_SCHEMA.dup.tap { |s| s.delete("oneOf") })
      }
      RAW_SCHEMA['oneOf'].each do |schema|
        type = schema['properties']['job_type']['const']
        SCHEMAS.merge!({ type => JSONSchemer.schema(schema) })
      end

      attributes \
        :cancelling,
        :created_at,
        :end_time,
        :estimated_end_time,
        :estimated_start_time,
        :job_type,
        :lazy,
        :reason,
        :rendered_path,
        :results_dir,
        :scheduler_id,
        :scheduler_state,
        :script_id,
        :start_time,
        :state,
        :stderr_path,
        :stdout_path,
        :submit_status,
        :submit_stderr,
        :submit_stdout,
        :version

      attribute :submission_answers, default: {}

      validates_with Job::Validator, on: :load,
        migrate_metadata: false
      validates_with Job::Validator, on: :save

      def self.from_script(script, answers, job)
        initial_metadata = {
          "created_at" => Time.now.rfc3339,
          "job_type" => "SUBMITTING",
          "script_id" => script.id,
          "rendered_path" => File.join(job.job_dir, script.script_name),
          "version" => SCHEMA_VERSION,
          "submission_answers" => answers,
        }
        path = File.join(job.job_dir, "metadata.yaml")
        new(initial_metadata, path, job)
      end

      def with_save_point(&block)
        raise "Nested calls to with_save_point unsupported" unless @save_point.nil?
        @save_point = @hash.deep_dup
        yield
      ensure
        @save_point = nil
      end

      def restore_save_point
        @hash = @save_point
        @save_point = nil
      end

      def persisted?
        File.exist?(path)
      end

      def job_type
        # The job_type is used within the validation, thus the metadata may
        # not be hash.
        @hash.is_a?(Hash) ? @hash["job_type"] : nil
      end

      def job
        @parent
      end
    end
  end
end

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
require 'json_schemer'

module FlightJob
  class Task < ApplicationModel
    STATES = Job::STATES

    # Tasks have a deliberately *similar* metadata syntax to SINGLETON jobs
    # Proceed with caution before introducing a deviation
    SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => [
        "version", 'state', 'stdout_path', 'stderr_path', "scheduler_state"
      ],
      "properties" => {
        # Required
        "version" => { "const" => 1 },
        "scheduler_state" => { "type" => "string", "minLength" => 1 },
        "state" => { "enum" => STATES },
        "stdout_path" => { "type" => "string", "minLength" => 1 },
        "stderr_path" => { "type" => "string", "minLength" => 1 },
        # Optional
        #
        # NOTE: The transient dependency between 'state' and times
        # are enforced by the monitor scripts.
        #
        # It is assumed they metadata will not be edited manually,
        # and thus will remain accurate.
        "estimated_start_time" => { "type" => ['date-time', 'null'] },
        "estimated_end_time" => { "type" => ['date-time', 'null'] },
        "start_time" => { "type" => ["date-time", "null"] },
        "end_time" => { "type" => ["date-time", "null"] },
        "reason" => { "type" => ["string", "null"] },
      }
    })

    # The job_id/task_index is stored within the metadata_path,
    # and must be injected onto the object
    attr_accessor :job_id, :index
    validates :job_id, presence: true
    validates :index, presence: true

    validate on: [:load, :save_metadata] do
      # Run the initial schema, followed by the specific one
      schema_errors = SCHEMA.validate(metadata).to_a

      # Add the schema errors if any
      unless schema_errors.empty?
        FlightJob.logger.debug("The following metadata file is invalid: #{metadata_path}\n") do
          JSON.pretty_generate(schema_errors)
        end
        errors.add(:metadata, 'is invalid')
      end
    end

    def tag
      "#{job_id}.#{index}"
    end

    def metadata_path
      @metadata_path ||= File.join(task_dir, "metadata.#{index}.yaml")
    end

    def metadata
      @metadata ||= if File.exists? metadata_path
        YAML.load File.read(metadata_path)
      else
        { "version" => 1 }
      end
    end

    private

    # NOTE: Requires parity with job_dir
    def task_dir
      @task_dir ||= File.join(FlightJob.config.jobs_dir, job_id, 'tasks')
    end
  end
end


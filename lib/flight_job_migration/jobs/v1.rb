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

require 'json_schemer'

module FlightJobMigration
  class MigrationError < FlightJob::InternalError; end

  module Jobs
    SCHEMA_V0 = JSONSchemer.schema(
      YAML.load(File.read Flight.config.join_schema_path('version0.yaml'))
    )
    SCHEMA_V1_RAW = YAML.load(
      File.read Flight.config.join_schema_path("version1.yaml")
    )
    SCHEMA_V1_SINGLETON = JSONSchemer.schema(
      SCHEMA_V1_RAW["oneOf"].find do |schema|
        schema["properties"]["job_type"]["const"] == "SINGLETON"
      end
    )
    SCHEMA_V1_FAILED_SUBMISSION = JSONSchemer.schema(
      SCHEMA_V1_RAW["oneOf"].find do |schema|
        schema["properties"]["job_type"]["const"] == "FAILED_SUBMISSION"
      end
    )

    MigrateV1 = Struct.new(:job_dir) do
      def self.load_all
        Dir.glob(File.join(Flight.config.jobs_dir, '*')).map do |dir|
          new(dir)
        end
      end

      def migrate
        migrate!
      rescue
        Flight.logger.error "Failed to migrate job '#{File.basename(job_dir)}'"
        Flight.logger.debug $!
      end

      def migrate!
        Flight.logger.info "Migrating job '#{id}'"
        validate_original
        case original['submit_status']
        when 0
          migrate_singleton
        else
          metadata['job_type'] = 'FAILED_SUBMISSION'
        end
        save_metadata
      end

      # Checks if the selected metadata is already the correct version
      def applicable?
        return true unless original["version"]
        original["version"] < 1
      rescue
        # Attempt to "run" the V1 migration on error
        # This is used to trigger logging
        return true
      end

      private

      def id
        File.basename(job_dir)
      end

      def validate_original
        errors = SCHEMA_V0.validate(original).to_a
        return if errors.empty?
        Flight.logger.error "Failed to validate (version 0): #{metadata_path}"
        Flight.logger.debug JSON.pretty_generate(errors)
        raise MigrationError, "Metadata is invalid: #{metadata_path}"
      end

      def validate_metadata
        schema = case metadata["job_type"]
                 when 'SINGLETON'
                   SCHEMA_V1_SINGLETON
                 else
                   SCHEMA_V1_FAILED_SUBMISSION
                 end
        errors = schema.validate(metadata).to_a
        return if errors.empty?
        Flight.logger.error "Failed to validate (version 1): #{metadata_path}"
        Flight.logger.debug JSON.pretty_generate(errors)
        raise MigrationError, "Metadata is invalid: #{metadata_path}"
      end

      def migrate_singleton
        metadata["job_type"] = 'SINGLETON'
        metadata.merge!(
          original.slice("state", "reason", "results_dir")
        )

        case metadata['state']
        when 'PENDING'
          metadata['estimated_start_time'] = original['start_time']
          metadata['estimated_end_time'] = original['end_time']
        when 'RUNNING'
          metadata['start_time'] = original['start_time']
          metadata['estimated_end_time'] = original['end_time']
        else
          metadata['start_time'] = original['start_time']
          metadata['end_time'] = original['end_time']
        end

        # The following can be omitted but not empty
        opts = original.slice('stdout_path', 'stderr_path')
                       .reject { |_, v| ["", nil].include?(v) }
                       .to_h
        metadata.merge!(opts)

        # The following where previously optional, but are now required
        metadata['scheduler_id'] = original['scheduler_id'] || 'unknown'
        metadata['scheduler_state'] = original['scheduler_state'] || 'unknown'
      end

      def original
        @original ||= if File.exists? metadata_path
                        YAML.load File.read(metadata_path)
                      else
                        raise MigrationError, "File does not exist: #{metadata_path}"
                      end
      end

      def metadata
        @metadata ||= original.slice(
          "created_at", "script_id", "submit_status", "submit_stdout", "submit_stderr",
          "rendered_path"
        ).tap do |data|
          data["version"] = 1
          data["rendered_path"] ||= generate_rendered_path

          # Some earlier jobs appear to be missing 'created_at'? TBC
          data["created_at"] ||= Time.at(0).to_datetime.rfc3339
        end
      end

      def save_metadata
        validate_metadata
        File.write backup_metadata_path, YAML.dump(original)
        File.write metadata_path, YAML.dump(metadata)
        Flight.logger.warn "Migrated job '#{id}' to version 1"
      end

      def metadata_path
        File.join(job_dir, 'metadata.yaml')
      end

      def backup_metadata_path
        File.join(job_dir, '.metadata.v0.yaml')
      end

      # Legacy Jobs may not have a rendered path
      # A dummy script is generated form them
      def generate_rendered_path
        File.join(job_dir, 'missing-script.sh').tap do |path|
          FileUtils.touch path
        end
      end

      def backup_results_dir
        File.join(job_dir, 'results')
      end
    end
  end
end

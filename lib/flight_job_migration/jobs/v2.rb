#==============================================================================
## Copyright (C) 2021-present Alces Flight Ltd.
##
## This file is part of Flight Job.
##
## This program and the accompanying materials are made available under
## the terms of the Eclipse Public License 2.0 which is available at
## <https://www.eclipse.org/legal/epl-2.0>, or alternative license
## terms made available by Alces Flight Ltd - please direct inquiries
## about licensing to licensing@alces-flight.com.
##
## Flight Job is distributed in the hope that it will be useful, but
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
## IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
## OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
## PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
## details.
##
## You should have received a copy of the Eclipse Public License 2.0
## along with Flight Job. If not, see:
##
##  https://opensource.org/licenses/EPL-2.0
##
## For more information on Flight Job, please visit:
## https://github.com/openflighthpc/flight-job
##===========================================================================

require 'json_schemer'
require_relative 'base'

module FlightJobMigration
  module Jobs
    class MigrateV2 < Base
      RAW_SCHEMA = JSON.parse(File.read(Flight.config.join_schema_path('version2.json')))
      SCHEMAS = {
        common: JSONSchemer.schema(RAW_SCHEMA.dup.tap { |s| s.delete("oneOf") })
      }
      RAW_SCHEMA['oneOf'].each do |schema|
        type = schema['properties']['job_type']['const']
        SCHEMAS.merge!({ type => JSONSchemer.schema(schema) })
      end

      def migrate!
        results_dir = pre_metadata['results_dir']
        create_control_file(results_dir)
        new_metadata.delete('results_dir')
        increment_version
        save_metadata
      end

      def applicable?
        pre_metadata["version"] == 1
      rescue
        Flight.logger.error "Error determining if migrate v2 is applicable to job '#{@job_id}'"
        Flight.logger.debug $!
        return false
      end

      private

      def assert_new_metadata_valid
        schema_errors = SCHEMAS[:common].validate(new_metadata).to_a
        if schema_errors.empty?
          schema_errors = SCHEMAS[new_metadata['job_type']].validate(new_metadata).to_a
        end
        unless schema_errors.empty?
          Flight.logger.info "Migrated metadata is invalid: #{@job_id}"
          JSONSchemaErrorLogger.new(schema_errors, :debug).log
          raise MigrationError, "Migrated metadata is invalid: #{@job_id}"
        end
      end

      def create_control_file(results_dir)
        controls_file = File.join(@job_dir, "controls", "results_dir")
        FileUtils.mkdir_p(File.dirname(controls_file))
        File.write(controls_file, results_dir)
      end
    end
  end
end

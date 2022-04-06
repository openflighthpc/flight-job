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
  class Job < ApplicationModel
    class Validator < ActiveModel::Validator
      def validate(metadata)
        validate_schema(metadata)
        migrate_metadata(metadata) if options[:migrate_metadata]
        add_and_log_errors(metadata)
      end

      private

      def validate_schema(metadata)
        @schema_errors = SCHEMAS[:common].validate(metadata.to_hash).to_a
        if @schema_errors.empty?
          @schema_errors = SCHEMAS[metadata['job_type']].validate(metadata.to_hash).to_a
        end
      end

      def add_and_log_errors(metadata)
        unless @schema_errors.empty?
          Flight.logger.info "Job '#{metadata.job.id.to_s}' metadata is invalid"
          JSONSchemaErrorLogger.new(@schema_errors, :info).log
          metadata.errors.add(:metadata, 'is invalid')
        end
      end

      # This isn't really validation, but we want to run it every time a job
      # loads, but only after it has been validated.
      #
      # XXX Extract to an after_validate callback.
      def migrate_metadata(metadata)
        job = metadata.job
        if @schema_errors.empty?
          FileUtils.rm_f(job.failed_migration_path)
        elsif File.exist?(job.failed_migration_path)
          Flight.logger.warn "Skipping job '#{job.id}' migration as it previously failed!"
        else
          if FlightJobMigration::Jobs.migrate(job.job_dir)
            metadata.reload
            validate_schema(metadata)
          else
            # Flag the failure
            FileUtils.touch job.failed_migration_path
          end
        end
      end
    end
  end
end

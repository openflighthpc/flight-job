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
      def validate(job)
        adjust_active_index(job) if options[:adjust_active_index]
        validate_schema(job)
        migrate_metadata(job) if options[:migrate_metadata]
        add_and_log_errors(job)
      end

      private

      def validate_schema(job)
        @schema_errors = SCHEMAS[:common].validate(job.metadata).to_a
        if @schema_errors.empty?
          @schema_errors = SCHEMAS[job.metadata['job_type']].validate(job.metadata).to_a
        end
      end

      def add_and_log_errors(job)
        unless @schema_errors.empty?
          Flight.logger.info "Job '#{job.id.to_s}' metadata is invalid"
          JSONSchemaErrorLogger.new(@schema_errors, :info).log
          job.errors.add(:metadata, 'is invalid')
        end
      end

      # This isn't really validation, but we want to run it every time a job
      # loads.
      #
      # XXX Extract to an `on_loaded` hook/callback?
      def adjust_active_index(job)
        if job.terminal?
          FileUtils.rm_f job.active_index_path
        else
          FileUtils.touch job.active_index_path
        end
      end

      # This isn't really validation, but we want to run it every time a job
      # loads.
      #
      # XXX Extract to an `on_loaded` hook/callback?
      def migrate_metadata(job)
        if @schema_errors.empty?
          FileUtils.rm_f job.failed_migration_path
        elsif File.exists? job.failed_migration_path
          Flight.logger.warn "Skipping job '#{job.id}' migration as it previously failed!"
        else
          if FlightJobMigration::Jobs.migrate(job.job_dir)
            job.reload_metadata
            @schema_errors = SCHEMAS[:common].validate(job.metadata).to_a
            if @schema_errors.empty?
              @schema_errors = SCHEMAS[job.metadata['job_type']].validate(job.metadata).to_a
            end
          else
            # Flag the failure
            FileUtils.touch job.failed_migration_path
          end
        end
      end
    end
  end
end

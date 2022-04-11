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
    # Manages attempts to migrate a job's metadata.yaml to a new schema
    # version.  The migration is performed by FlightJobMigration::Jobs.
    class MigrateMetadata
      def self.after_initialize(job)
        return unless job.persisted?

        if job.valid?
          FileUtils.rm_f(job.failed_migration_path)
        elsif File.exist?(job.failed_migration_path)
          Flight.logger.info "Skipping job '#{job.id}' migration as it previously failed!"
        else
          if FlightJobMigration::Jobs.migrate(job.job_dir)
            job.metadata.reload
            job.validate
          else
            # Flag the failure
            FileUtils.touch(job.failed_migration_path)
          end
        end
      end
    end
  end
end

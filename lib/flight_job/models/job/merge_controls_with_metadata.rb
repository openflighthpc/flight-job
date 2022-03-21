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
    # Depending on how a job is submitted to the scheduler, some of the
    # metadata may be in a controls_file instead of the metadata.  This class
    # merges such controls_files to the metadata to provide a consistent
    # access mechanism.
    class MergeControlsWithMetadata
      class << self
        def after_initialize(job)
          return unless job.persisted?
          return unless job.metadata.is_a?(Hash)

          merge_control_file(job, "scheduler_id")
          merge_control_file(job, "submit_status", transform: :to_i)
          merge_job_type(job)
        end

        private

        def merge_control_file(job, key, transform: nil)
          job.metadata[key] ||=
            begin
              value = job.controls_file(key).read
              value = transform_value(value, transform)
              Flight.logger.debug("Setting #{key} from controls file to #{value.inspect}")
              value
            end
        end

        def transform_value(value, transform)
          return value if value.nil? || transform.nil?

          if transform.respond_to?(:call)
            transform.call(value)
          else
            value.send(transform)
          end
        end

        def merge_job_type(job)
          meta_job_type = job.metadata["job_type"]
          if meta_job_type.blank? || meta_job_type == "SUBMITTING"
            controls_job_type = job.controls_file("job_type").read
            if controls_job_type.present?
              Flight.logger.debug("Setting job_type from controls file to #{controls_job_type.inspect}")
              job.metadata["job_type"] = controls_job_type
            end
          end
        end
      end
    end
  end
end

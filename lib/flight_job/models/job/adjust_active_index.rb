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
    # Manages a job's active index file.
    #
    # The active index file is created when a job is saved and removed when the
    # job reaches a terminal state.
    #
    # This file is a performance optimisation to allow for quickly determining
    # which jobs have not yet reached a terminal state.
    class AdjustActiveIndex
      def self.after_initialize(job)
        return unless job.persisted?
        adjust_active_index(job)
      end

      def self.after_save(job)
        adjust_active_index(job)
      end

      def self.adjust_active_index(job)
        if job.terminal?
          Flight.logger.debug("Removing active index file for terminal job #{job.id}")
          FileUtils.rm_f active_index_path(job)
        else
          Flight.logger.debug("Touching active index file for non-terminal job #{job.id}")
          FileUtils.touch active_index_path(job)
        end
      end

      def self.active_index_path(job)
        File.join(job.job_dir, 'active.index')
      end
      
    end
  end
end

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
    # This file is a performance optimisation to allow for quickly determining
    # which jobs have not yet reached a terminal state.
    #
    # XXX The active index file may also be updated when a job is saved.
    # Managing that should also become the responsibility of this class.
    class AdjustActiveIndex < Job
      def self.after_initialize(job)
        return unless job.persisted?
        job.edit_active_index
      end

      def self.after_save(job)
        job.edit_active_index
      end
    end

    def edit_active_index
      if terminal?
        Flight.logger.debug("Removing active index file for terminal job #{id}")
        FileUtils.rm_f active_index_path
      else
        Flight.logger.debug("Touching active index file for non-terminal job #{id}")
        FileUtils.touch active_index_path
      end
    end

    def active_index_path
      @active_index_path ||= File.join(job_dir, 'active.index')
    end
  end
end

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

require 'output_mode'

module FlightJob
  class Outputs::ListJobs < OutputMode::Formatters::Index
    def register_id
      register(header: 'ID', row_color: :yellow) { |j| j.id }
    end

    def register_script_id
      register(header: 'Script ID') { |j| j.script_id }
    end

    def register_sched_id
      register(header: 'Sched. ID') { |j| j.scheduler_id }
    end

    def register_state
      register(header: 'State') { |j| j.state }
    end

    # NOTE: The estimated time *may* be displayed in an interactive shell
    # This must not affect the non-interactive output
    def register_shared_times
      register(header: 'Submitted at', &:created_at)
      register(header: 'Started at') do |job|
        if job.actual_start_time || !interactive?
          job.actual_start_time
        elsif job.estimated_start_time
          time = format(job.estimated_start_time)
          "#{time} (Est.)"
        end
      end
      register(header: 'Ended at') do |job|
        if job.actual_end_time || !interactive?
          job.actual_end_time
        elsif job.estimated_end_time
          time = format(job.estimated_end_time)
          "#{time} (Est.)"
        end
      end
    end

    def register_paths
      register(header: 'StdOut Path', &:stdout_path)
      register(header: 'StdErr Path', &:stderr_path)
      register(header: 'Results Dir', &:results_dir)
    end

    constructor do
      if interactive?
        register_id
        register_sched_id
        register_script_id

        register_state

        register_shared_times

        if verbose?
          register_paths
        end
      else
        # NOTE The following cannot be re-ordered without introducing a breaking change
        register_id
        register_script_id

        register_sched_id
        register_state

        register(header: 'Submit Status') { |j| j.submit_status }

        register_shared_times

        register_paths
        register(header: 'Estimated Start',  &:estimated_start_time)
        register(header: 'Estimated Finish', &:estimated_end_time)
      end
    end
  end
end

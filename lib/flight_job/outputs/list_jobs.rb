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
    # Used to dynamically format the time based
    def format_dynamic_time(time, long_date: false)
      # Modify the time to be local
      time.localtime

      # Display the time if the same day
      if same_day?(time)
        time.strftime("%H:%M")
      # Display the date
      elsif long_date
        time.strftime("%d/%m/%y")
      else
        time.strftime("%d/%m")
      end
    end

    # Checks if a given time is the same day
    # NOTE: Must have the same offset
    def same_day?(time)
      [:day, :mon, :year].all? { |m| [time_now, time].map(&m).uniq.length == 1 }
    end

    # Used to determine the current day
    def time_now
      @time_now ||= Time.now
    end

    # Override the "format" to allow for dynamic times
    def format(value, **config)
      if value.is_a?(Time) && !verbose?
        format_dynamic_time(value, long_date: config[:long_date])
      else
        super
      end
    end

    def register_ids
      register(header: 'ID', row_color: :yellow) { |j| j.id }
      register(header: 'Script ID') { |j| j.script_id }
      register(header: 'Sched. ID') { |j| j.scheduler_id }
    end

    def register_state
      register(header: 'State') { |j| j.state }
    end

    # NOTE: The estimated time *may* be displayed in an interactive shell
    # This must not affect the non-interactive output
    def register_shared_times
      register(header: 'Submitted', long_date: true, &:created_at)
      register(header: 'Started') do |job|
        if job.actual_start_time || !interactive?
          job.actual_start_time
        elsif job.estimated_start_time
          time = format(job.estimated_start_time)
          "#{time} (Est.)"
        end
      end
      register(header: 'Ended') do |job|
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
        register_ids
        register_state

        register_shared_times

        register_paths if verbose?
      else
        # NOTE The following cannot be re-ordered without introducing a breaking change
        register_ids
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

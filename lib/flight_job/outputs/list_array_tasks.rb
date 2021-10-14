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
  class Outputs::ListArrayTasks < OutputMode::Formatters::Index
    def fetch_time(task, key)
      time = task.metadata[key]
      time ? Time.parse(time) : time
    end

    def register_all
      register(header: 'Index', row_color: :yellow, &:index)
      register(header: 'Job ID', &:job_id)
      register(header: 'Sched. ID', &:scheduler_id)
      register(header: 'State') { |t| t.metadata['state'] }

      register(header: 'Started at') { |t| fetch_time(t, 'start_time') }
      register(header: 'Ended at') { |t| fetch_time(t, 'end_time') }

      if verbose?
        register(header: 'Estimated Start') { |t| fetch_time(t, 'estimated_start_time') }
        register(header: 'Estimated Finish') { |t| fetch_time(t, 'estimated_end_time') }

        register(header: 'StdOut Path') { |t| t.metadata['stdout_path'] }
        register(header: 'StdErr Path') { |t| t.metadata['stderr_path'] }
      end
    end
  end
end

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
  class Outputs::InfoArrayTask < OutputMode::Formatters::Show

    alias_method :task, :object

    def merged_stderr?
      task.metadata.slice('stdout_path', 'stderr_path').values.uniq.length == 1
    end

    def fetch_time(key)
      time = task.metadata[key]
      time ? Time.parse(time) : time
    end

    def register_all
      template(<<~ERB) if humanize?
        <% each(:default) do |value, padding:, field:| -%>
        <%
            # Apply the colours
            value = pastel.green value
            field = pastel.blue.bold field
        -%>
        <%= padding -%><%= pastel.blue.bold field -%><%= pastel.bold ':' -%> <%= value %>
        <% end -%>
      ERB

      register(header: 'Index', &:index)
      register(header: 'Job ID', &:job_id)
      register(header: 'Scheduler ID', &:scheduler_id)
      register(header: 'State') { |t| t.metadata['state'] }

      if task.metadata['start_time'] || verbose?
        register(header: 'Started at') { fetch_time('start_time') }
      else
        register(header: 'Estimated Start') { fetch_time('estimated_start_time') }
      end

      if task.metadata['end_time'] || verbose?
        register(header: 'Ended at') { fetch_time('end_time') }
      else
        register(header: 'Estimated Finish') { fetch_time('estimated_end_time') }
      end

      if verbose?
        register(header: 'Estimated start') { fetch_time('estimated_start_time') }
        register(header: 'Estimated start') { fetch_time('estimated_end_time') }
      end

      path_header = merged_stderr? && !verbose? ? 'Output Path' : 'Stdout Path'
      register(header: path_header) { |t| t.metadata['stdout_path'] }
      if verbose?
        register(header: 'Stderr Path') { |t| t.metadata['stderr_path'] }
      end

      register(header: 'Results Dir') { |t| t.job.metadata['results_dir'] }
    end
  end
end

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
    constructor do
      register(header: 'ID', row_color: :yellow) { |j| j.id }
      register(header: 'Script ID') { |j| j.script_id }

      if verbose?
        register(header: 'Sched. ID') { |j| j.scheduler_id }
      end
      register(header: 'State') { |j| j.state }

      # Show a boolean in the "simplified" output, and the exit code in the verbose
      # NOTE: The headers are intentionally toggled between outputs
      if verbose?
        register(header: 'Submit Status') { |j| j.submit_status }
      else
        register(header: 'Submitted') { |j| j.submit_status == 0 }
      end

      register(header: 'Submitted at') do |job|
        if verbose?
          job.created_at
        else
          DateTime.rfc3339(job.created_at).strftime('%d/%m/%y %H:%M')
        end
      end

      register(header: 'Started at') do |job|
        Outputs.format_time(job.actual_start_time, verbose?)
      end
      register(header: 'Ended at') do |job|
        Outputs.format_time(job.actual_end_time, verbose?)
      end

      if verbose?
        register(header: 'StdOut Path', &:stdout_path)
        register(header: 'StdErr Path', &:stderr_path)
        register(header: 'Results Dir', &:results_dir)

        register(header: 'Estimated Start',  &:estimated_start_time)
        register(header: 'Estimated Finish', &:estimated_end_time)
      end
    end
  end
end

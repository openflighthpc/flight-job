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
  class Outputs::InfoJob < OutputMode::Formatters::Show
    def initialize(job, **opts)
      super(job, **opts)
      @submit = verbose? || job.submit_status != 0
    end

    def submit?
      @submit ? true : false
    end

    def format_row(field, value, padding)
      f = pastel.blue.bold field
      s = pastel.bold ':'
      v = pastel.green value
      "#{padding}#{f}#{s} #{v}"
    end

    alias_method :job, :object

    constructor do
      template(<<~ERB) if interactive?
        <% each(:default) do |value, padding:, field:| -%>
        <%= format_row(field, value, padding) %>
        <% end -%>
        <%
          submit_outputs = callables.select { |proc| proc.config[:section] == :submit }
          if verbose? || submit?
        -%>

        <%= pastel.blue.bold "Submit Stdout" -%><%= pastel.bold ':' %>
        <%= pastel.green format(job.submit_stdout) %>
        <%= pastel.blue.bold "Submit Stderr" -%><%= pastel.bold ':' %>
        <%= pastel.green format(job.submit_stderr) %>
        <% end -%>
      ERB

      register(header: 'ID') { job.id }
      register(header: 'Script ID') { job.script_id }
      register(header: 'Scheduler ID') { job.scheduler_id }
      register(header: 'State') { job.state }

      # Show a boolean in the "simplified" output, and the exit code in the verbose
      # NOTE: There is a rendering issue of integers into the TSV output. Needs investigation
      if verbose?
        register(header: 'Submit Status') { job.submit_status.to_s }
      else
        register(header: 'Submitted') { job.submit_status == 0 }
      end

      register(header: 'Submitted at', &:created_at)

      if job.actual_start_time || verbose?
        register(header: 'Started at', &:actual_start_time)
      else
        register(header: 'Estimated Start', &:estimated_start_time)
      end

      if job.actual_end_time || verbose?
        register(header: 'Ended at', &:actual_end_time)
      else
        register(header: 'Estimated Finish', &:estimated_end_time)
      end

      stdout_header = if job.stdout_path == job.stderr_path && !verbose?
        'Output Path'
      else
        'Stdout Path'
      end
      register(header: stdout_header) { job.stdout_path }
      if verbose?
        register(header: 'Stderr Path') { job.stderr_path }
      end

      # Display the stdout/stderr callables in non-interactive
      # They are hard rendered into the interactive template
      unless interactive?
        register(header: 'Submit Stdout') { job.submit_stdout }
        register(header: 'Submit Stderr') { job.submit_stderr }
      end

      # NOTE: The following appear after the submit attributes in the non-interactive output. This
      # maintains the column order and backwards compatibility.
      #
      # The submit columns will always be sorted to the bottom in the interactive outputs.
      #
      # Consider reordering on the next major version bump.
      register(header: 'Results Dir') { job.results_dir }
      if verbose?
        register(header: 'Estimated start', &:estimated_start_time)
        register(header: 'Estimated end', &:estimated_end_time)
      end

      register(header: "Desktop ID:", &:desktop_id)
    end
  end
end


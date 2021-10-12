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

    def register_ids
      register(header: 'ID') { job.id }
      register(header: 'Script ID') { job.script_id }
      register(header: 'Scheduler ID') { job.scheduler_id }
    end

    # Show a boolean in the "simplified" output, and the exit code in the verbose
    # NOTE: There is a rendering issue of integers into the TSV output. Needs investigation
    def register_status
      if verbose?
        register(header: 'Submit Status') { job.submit_status.to_s }
      else
        register(header: 'Submitted') { job.submit_status == 0 }
      end
    end

    def register_paths
      stdout_header = if job.stdout_path == job.stderr_path && !verbose?
        'Output Path'
      else
        'Stdout Path'
      end
      register(header: stdout_header) { job.stdout_path }
      if verbose?
        register(header: 'Stderr Path') { job.stderr_path }
      end
    end

    def register_submit_std
      register(header: 'Submit Stdout') { job.submit_stdout }
      register(header: 'Submit Stderr') { job.submit_stderr }
    end

    def register_times(force: nil)
      a_start = ->() { register(header: 'Started at', &:actual_start_time) }
      a_end   = ->() { register(header: 'Ended at', &:actual_end_time) }
      e_start = ->() { register(header: 'Estimated Start', &:estimated_start_time) }
      e_end   = ->() { register(header: 'Estimated Finish', &:estimated_end_time) }

      unless [:actual, :estimated, nil].include? force
        raise InternalError, "Unrecognised force flag: #{force}"
      end

      case force
      when :actual
        a_start.call
        a_end.call
      when :estimated
        e_start.call
        e_end.call
      when :inferred
        job.actual_start_time ? a_start.call : e_start.call
        job.actual_end_time   ? a_end.call   : e_end.call
      else
        raise InternalError, "Unrecognised force flag: #{force}"
      end
    end

    def register_all
      template(<<~ERB) if humanize?
        <% each(:default) do |value, padding:, field:| -%>
        <%=   format_row(field, value, padding) %>
        <% end -%>
        <% if submit? -%>

        <%=   pastel.blue.bold "Submit Stdout" -%><%= pastel.bold ':' %>
        <%=   pastel.green format(job.submit_stdout) %>
        <%=   pastel.blue.bold "Submit Stderr" -%><%= pastel.bold ':' %>
        <%=   pastel.green format(job.submit_stderr) %>
        <% end -%>
      ERB

      register_ids
      register(header: 'State') { job.state }
      register_status

      register(header: 'Submitted at', &:created_at)

      register_times force: (verbose? ? :actual : :inferred)

      register_paths

      # Display the stdout/stderr callables in non-interactive
      # They are hard rendered into the interactive template
      register_submit_std unless humanize?

      # NOTE: The following appear after the submit attributes in the non-interactive output. This
      # maintains the column order and backwards compatibility.
      #
      # The submit columns will always be sorted to the bottom in the interactive outputs.
      #
      # Consider reordering on the next major version bump.
      register(header: 'Results Dir') { job.results_dir }
      register_times(force: :estimated) if verbose?

      register(header: "Desktop ID", &:desktop_id)
    end
  end
end


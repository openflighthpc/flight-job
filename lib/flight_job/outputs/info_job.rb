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
  module Outputs::InfoJob
    extend OutputMode::TLDR::Show

    TEMPLATE = <<~ERB
      <% verbose = output.context[:verbose] -%>
      <% each(:default) do |value, padding:, field:| -%>
      <%
          # Apply the colours
          value = pastel.green value
          field = pastel.blue.bold field
      -%>
      <%= padding -%><%= pastel.blue.bold field -%><%= pastel.bold ':' -%> <%= value %>
      <% end -%>
      <%
        submit_outputs = output.procs.select { |proc| proc.config[:section] == :submit }
        if verbose || output.context[:submit]
      -%>

      <%= pastel.blue.bold "Submit Stdout" -%><%= pastel.bold ':' %>
      <%= pastel.green submit_outputs.first.call(model) %>
      <%= pastel.blue.bold "Submit Stderr" -%><%= pastel.bold ':' %>
      <%= pastel.green submit_outputs.last.call(model) %>
      <% end -%>
    ERB

    register_attribute(header: 'ID') { |j| j.id }
    register_attribute(header: 'Script ID') { |j| j.script_id }
    register_attribute(header: 'Scheduler ID') { |j| j.scheduler_id }
    register_attribute(header: 'State') { |j| j.state }

    # Show a boolean in the "simplified" output, and the exit code in the verbose
    # NOTE: There is a rendering issue of integers into the TSV output. Needs investigation
    register_attribute(header: 'Submitted', verbose: false) { |j| j.submit_status == 0 }
    register_attribute(header: 'Submit Status', verbose: true) { |j| j.submit_status.to_s }

    register_attribute(header: 'Submitted at') do |job, verbose:|
      if verbose
        job.created_at
      else
        DateTime.rfc3339(job.created_at).strftime('%d/%m/%y %H:%M')
      end
    end

    start_header = ->(job, verbose:) do
      job.actual_start_time || verbose ? 'Started at' : 'Estimated Start'
    end
    register_attribute(header: start_header) do |job, verbose:|
      if job.actual_start_time || verbose
        job.format_actual_start_time(verbose)
      else
        job.format_estimated_start_time(false)
      end
    end

    end_header = ->(job, verbose:) do
      job.actual_end_time || verbose ? 'Ended at' : 'Estimated Finish'
    end
    register_attribute(header: end_header) do |job, verbose:|
      if job.actual_end_time || verbose
        job.format_actual_end_time(verbose)
      else
        job.format_estimated_end_time(false)
      end
    end

    path_header = ->(job, verbose:) do
      if job.stdout_path == job.stderr_path && !verbose
        'Output Path'
      else
        'Stdout Path'
      end
    end
    register_attribute(header: path_header) { |j| j.stdout_path }
    register_attribute(header: 'Stderr Path', verbose: true) { |j| j.stderr_path }

    register_attribute(section: :submit, header: 'Submit Stdout') do |job|
      job.submit_stdout
    end
    register_attribute(section: :submit, header: 'Submit Stderr') do |job|
      job.submit_stderr
    end

    # NOTE: The following appear after the submit attributes in the non-interactive output. This
    # maintains the column order and backwards compatibility.
    #
    # The submit columns will always be sorted to the bottom in the interactive outputs.
    #
    # Consider reordering on the next major version bump.
    register_attribute(header: 'Results Dir') { |j| j.results_dir }
    register_attribute(verbose: true, header: 'Estimated start') do |job|
      job.format_estimated_start_time(true)
    end
    register_attribute(verbose: true, header: 'Estimated end') do |job|
      job.format_estimated_end_time(true)
    end

    def self.build_output(**opts)
      submit = opts.delete(:submit)
      super(template: TEMPLATE, context: { submit: submit }, **opts)
    end
  end
end


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
      <%
        verbose = output.context[:verbose]
        main = output.callables.config_select(:section, :main)
        paths = main.select(&:paths?)

        # Determine if the STDOUT/STDERR paths should be combined or
        # independently displayed
        if verbose || paths.map { |p| p.call(model) }.uniq.length != 1
          callables = OutputMode::Callables.new main.reject(&:combined?)
        else
          callables = OutputMode::Callables.new main.reject(&:paths?)
        end
      -%>
      <% callables.pad_each do |callable, padding:| -%>
      <%
          # Generates the value
          # NOTE: The output contains details about how to handle nil/true/false
          value = pastel.green callable.generator(output).call(model)
          header = pastel.blue.bold callable.config[:header]
      -%>
      <%= padding -%><%= header -%><%= pastel.bold ':' -%> <%= value %>
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

    register_attribute(section: :main, header: 'ID') { |j| j.id }
    register_attribute(section: :main, header: 'Script ID') { |j| j.script_id }
    register_attribute(section: :main, header: 'Scheduler ID') { |j| j.scheduler_id }
    register_attribute(section: :main, header: 'State') { |j| j.state }

    # Show a boolean in the "simplified" output, and the exit code in the verbose
    register_attribute(section: :main, header: 'Submitted', verbose: false) { |j| j.submit_status == 0 }
    # NOTE: There is a rendering issue of integers into the TSV output. Needs investigation
    register_attribute(section: :main, header: 'Submit Status', verbose: true) { |j| j.submit_status.to_s }

    register_attribute(section: :main, header: 'Created at') do |job, verbose:|
      if verbose
        job.created_at
      else
        DateTime.rfc3339(job.created_at).strftime('%d/%m/%y %H:%M')
      end
    end

    # NOTE: These could be the predicted times instead of the actual, consider
    # delineating the two
    register_attribute(section: :main, header: 'Started at') do |job, verbose:|
      if job.start_time.nil?
        nil
      elsif verbose
        job.start_time
      else
        DateTime.rfc3339(job.start_time).strftime('%d/%m/%y %H:%M')
      end
    end
    register_attribute(section: :main, header: 'Ended at') do |job, verbose:|
      if job.end_time.nil?
        nil
      elsif verbose
        job.end_time
      else
        DateTime.rfc3339(job.end_time).strftime('%d/%m/%y %H:%M')
      end
    end

    # NOTE: In interactive shells, the STDOUT/STDERR are merged together if they
    #       are the same. The 'modes' are boolean flags (similar to verbose/interactive)
    #       which are used to select the appropriate attributes.
    #
    #       As each attribute is defined independently, the headers can be changed without
    #       affecting the ability to pad the output.
    #
    # PS: The 'path' mode is a misnomer, it refers solely to the standard output/error paths
    register_attribute(section: :main, modes: [:paths], header: 'Stdout Path') { |j| j.stdout_path }
    register_attribute(section: :main, modes: [:paths], header: 'Stderr Path') { |j| j.stderr_path }
    register_attribute(section: :main, interactive: true, modes: [:combined], header: 'Output Path') { |j| j.stdout_path }

    register_attribute(section: :submit, header: 'noop') do |job|
      job.submit_stdout
    end
    register_attribute(section: :submit, header: 'noop') do |job|
      job.submit_stderr
    end

    # NOTE: The following appear after the submit attributes in the non-interactive output. This
    # maintains the column order and backwards compatibility.
    #
    # The submit columns will always be sorted to the bottom in the interactive outputs.
    #
    # Consider reordering on the next major version bump.
    register_attribute(section: :main, header: 'Output Dir') { |j| j.output_dir }

    def self.build_output(**opts)
      submit = opts.delete(:submit)
      if opts.delete(:json)
        JSONRenderer.new(false, opts[:interactive])
      else
        super(template: TEMPLATE, context: { submit: submit }, **opts)
      end
    end
  end
end


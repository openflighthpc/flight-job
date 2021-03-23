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
      <% each(:main) do |value, field:, padding:, **_| -%>
      <%= padding -%><%= pastel.blue.bold field -%><%= pastel.bold ':' -%> <%= pastel.green value %>
      <% end -%>
      <%
        submit_outputs = output.procs.select { |proc| proc.config[:section] == :submit }
        unless submit_outputs.empty?
      -%>

      <%= pastel.blue.bold "Submit Standard Out" -%><%= pastel.bold ':' %>
      <%= pastel.green submit_outputs.first.call(model) %>
      <%= pastel.blue.bold "Submit Standard Error" -%><%= pastel.bold ':' %>
      <%= pastel.green submit_outputs.last.call(model) %>
      <% end -%>
    ERB

    register_attribute(section: :main, header: 'ID') { |j| j.id }
    register_attribute(section: :main, header: 'Script ID') { |j| j.script_id }
    register_attribute(section: :main, header: 'Alt. ID') { |j| j.scheduler_id }
    register_attribute(section: :main, header: 'State') { |j| j.state }

    # Show a boolean in the "simplified" output, and the exit code in the verbose
    register_attribute(section: :main, header: 'Submitted', verbose: false) { |j| j.submit_status == 0 }
    # NOTE: There is a rendering issue of integers into the TSV output. Needs investigation
    register_attribute(section: :main, header: 'Submit Status', verbose: true) { |j| j.submit_status.to_s }

    # Toggle the format of the created at time
    register_attribute(section: :main, header: 'Created At', verbose: true) { |j| j.created_at }
    register_attribute(section: :main, header: 'Created At', verbose: false) do |job|
      DateTime.rfc3339(job.created_at).strftime('%d/%m/%y %H:%M')
    end

    # NOTE: These could be the predicted times instead of the actual, consider
    # delineating the two
    register_attribute(section: :main, header: 'Start Time', verbose: true) { |j| j.start_time }
    register_attribute(section: :main, header: 'Start Time', verbose: false) do |job|
      next nil unless job.start_time
      DateTime.rfc3339(job.start_time).strftime('%d/%m/%y %H:%M')
    end
    register_attribute(section: :main, header: 'End Time', verbose: true) { |j| j.end_time }
    register_attribute(section: :main, header: 'End Time', verbose: false) do |job|
      next nil unless job.end_time
      DateTime.rfc3339(job.end_time).strftime('%d/%m/%y %H:%M')
    end

    register_attribute(section: :main, header: 'StdOut Path') { |j| j.stdout_path }
    register_attribute(section: :main, header: 'StdErr Path') { |j| j.stderr_path }

    register_attribute(section: :submit, header: 'Submission STDOUT') do |job|
      job.submit_stdout
    end
    register_attribute(section: :submit, header: 'Submission STOUT') do |job|
      job.submit_stderr
    end

    def self.build_output(**opts)
      submit = opts.delete(:submit)
      if opts.delete(:json)
        JSONRenderer.new(false, opts[:interactive])
      else
        super(template: TEMPLATE, **opts).tap do |output|
          # OutputMode currently doesn't properly support escaping of the newlines
          # due to how it has wrapped the underlying CSV library
          case output
          when OutputMode::Outputs::Delimited
            output.config.merge! write_converters: [->(f) { f.to_s.dump.sub(/\A"/, '').sub(/"\Z/, '') }]

          # Toggles the STDOUT/STDERR display based on verbosity or if explicitly flagged
          when OutputMode::Outputs::Templated
            if !(opts[:verbose] || submit)
              output.procs.reject! { |c| c.config[:section] == :submit }
            end
          end
        end
      end
    end
  end
end


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
  module Outputs::InfoArrayTask
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
    ERB

    register_attribute(header: 'Index', &:index)
    register_attribute(header: 'Job ID', &:job_id)
    register_attribute(header: 'Scheduler ID') { |t| t.job.metadata['scheduler_id'] }
    register_attribute(header: 'State') { |t| t.metadata['state'] }

    start_header = ->(task, verbose:) do
      task.metadata['start_time'] || verbose ? 'Started at' : 'Estimated Start'
    end
    register_attribute(header: start_header) do |task, verbose:|
      if task.metadata['start_time'] || verbose
        Outputs.format_time(task.metadata['start_time'], verbose)
      else
        Outputs.format_time(task.metadata['estimated_start_time'], false)
      end
    end

    end_header = ->(task, verbose:) do
      task.metadata['end_time'] || verbose ? 'Ended at' : 'Estimated Finish'
    end
    register_attribute(header: end_header) do |task, verbose:|
      if task.metadata['end_time'] || verbose
        Outputs.format_time(task.metadata['end_time'], verbose)
      else
        Outputs.format_time(task.metadata['estimated_end_time'], false)
      end
    end

    register_attribute(verbose: true, header: 'Estimated start') do |task|
      Outputs.format_time(task.metadata['estimated_start_time'], false)
    end
    register_attribute(verbose: true, header: 'Estimated end') do |task|
      Outputs.format_time(task.metadata['estimated_end_time'], false)
    end

    path_header = ->(task, verbose:) do
      if task.metadata.slice('stdout_path', 'stderr_path').values.uniq.length == 1 && !verbose
        'Output Path'
      else
        'Stdout Path'
      end
    end
    register_attribute(header: path_header) { |t| t.metadata['stdout_path'] }
    register_attribute(header: 'Stderr Path', verbose: true) { |t| t.metadata['stderr_path'] }

    register_attribute(header: 'Results Dir') { |t| t.job.metadata['results_dir'] }

    def self.build_output(**opts)
      super(template: TEMPLATE, **opts)
    end
  end
end


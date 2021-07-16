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
  module Outputs::InfoScript
    extend OutputMode::TLDR::Show

    TEMPLATE = <<~ERB
      <% each(:main) do |value, field:, padding:, **_| -%>
      <%= padding -%><%= pastel.blue.bold field -%><%= pastel.bold ':' -%> <%= pastel.green value %>
      <% end -%>

      <%= pastel.blue.bold 'NOTES' -%><%= pastel.bold ':' %>
      <% each(:notes) do |value, **_| -%>
      <%= pastel.green value.chomp %>
      <% end -%>
    ERB

    register_attribute(section: :main, header: 'ID') { |s| s.id }
    # NOTE: The verbose output is at the end to avoid the order changing
    register_attribute(section: :main, header: 'Template ID') { |s| s.template_id }
    register_attribute(section: :main, header: 'File Name') { |s| s.script_name }
    register_attribute(section: :main, header: 'Path') { |s| s.workload_path }

    register_attribute(section: :main, header: 'Created at') do |script, verbose:|
      if verbose
        script.created_at
      else
        DateTime.rfc3339(script.created_at).strftime('%d/%m/%y %H:%M')
      end
    end

    register_attribute(section: :notes, header: 'Notes') { |s| s.notes }

    def self.build_output(**opts)
      super(template: TEMPLATE, **opts)
    end
  end
end

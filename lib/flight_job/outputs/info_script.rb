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
  class Outputs::InfoScript < OutputMode::Formatters::Show
    def register_all
      template(<<~ERB) if humanize?
        <% each(:main) do |value, field:, padding:, **_| -%>
        <%= padding -%><%= pastel.blue.bold field -%><%= pastel.bold ':' -%> <%= pastel.green value %>
        <% end -%>

        <%= pastel.blue.bold 'NOTES' -%><%= pastel.bold ':' %>
        <% each(:notes) do |value, **_| -%>
        <%= pastel.green value.chomp %>
        <% end -%>
      ERB

      register(section: :main, header: 'ID') { |s| s.id }
      # NOTE: The verbose output is at the end to avoid the order changing
      register(section: :main, header: 'Template ID') { |s| s.template_id }
      register(section: :main, header: 'File Name') { |s| s.script_name }
      register(section: :main, header: 'Path') { |s| s.script_path }

      register(section: :main, header: 'Created at') do |script|
        Time.parse script.created_at
      end

      register(section: :notes, header: 'Notes') { |s| s.notes }
    end
  end
end

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

require_relative '../markdown_renderer'

module FlightJob
  class Outputs::InfoTemplate
    TEMPLATE = ERB.new(<<~ERB, nil, '-')
      # <%= template_path -%> -- <%= id %>

      ## DESCRIPTION

      <%= metadata['synopsis'] %>
      <%= metadata['description'] -%><%= "\n" if metadata['description'] -%>

      ## LICENSE

      This work is licensed under a <%#= license -%> License.

      ## COPYRIGHT

      <%#= copyright -%>
    ERB

    def self.build_output(**opts)
      new(**opts)
    end

    def initialize(**opts)
      @opts = opts
    end

    def render(template)
      if erb?
        bind = nil
        template.instance_exec { bind = self.binding }
        MarkdownRenderer.new(TEMPLATE.result(bind)).wrap_markdown
      end
    end

    def erb?
      true
    end
  end
end

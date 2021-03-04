#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
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

require 'ostruct'
require 'erb'
require_relative '../markdown_renderer'

module FlightJob
  module Commands
    class ShowTemplate < Command
      TEMPLATE = <<~ERB
        # <%= id %>

        ## DESCRIPTION

        <%= synopsis %>
        <%= description -%><%= "\n" if description -%>

        ## LICENSE

        This work is licensed under a <%#= license -%> License.

        ## COPYRIGHT

        <%#= copyright -%>
      ERB
      ERB_TEMPLATE = ERB.new(TEMPLATE, nil, '-')

      def run
        bind = template.instance_exec { self.binding }
        rendered = ERB_TEMPLATE.result(bind)
        puts MarkdownRenderer.new(rendered).wrap_markdown
      end

      def template
        @template ||= load_template(args.first)
      end
    end
  end
end

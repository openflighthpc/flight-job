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
# This help formatter has been modified from commander-openflighthpc. All
# changes are made available under the EPL-2.0 mentioned above. The original
# work is available under the following licenses.
#
# The following license applies to changes made subsequent to the point
# this version was forked from the original upstream version available
# at <https://github.com/commander-rb/commander>.
#
# The MIT License (MIT)
#
# Copyright (c) 2017-present Alces Flight Ltd <licensing@alces-flight.com>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# The original license from the upstream version is included below:
#
# The MIT License (MIT)
#
# Copyright (c) 2008-2013 TJ Holowaychuk <tj@vision-media.ca>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#==============================================================================

module FlightJob
  class ProgramContext < Commander::HelpFormatter::ProgramContext
    def initialize(runner)
      super(runner)
      # Commander uses a decorate_binding mechanism which is incredible tricky
      # to use. It proved to be easier to monkey-patch the new methods unto
      # the runner object directly
      s = sections
      cbs = commands_by_section
      runner.define_singleton_method(:commands_by_section) { cbs }
      runner.define_singleton_method(:sections){ s }
    end

    def sections
      @sections ||= {
        ['template', 'templates'] => 'Templates:',
        ['script', 'scripts', 'script-notes'] => 'Scripts:',
        ['job', 'jobs'] => 'Jobs:'
      }
    end

    def command_prefix_order
      @command_prefix_order ||= ['list', 'create', 'submit', 'show', 'info', 'edit', 'delete']
    end

    def commands_by_section
      @commands_by_section ||= begin
        # Ignore aliases
        main_commands = @target.instance_variable_get(:@commands)
                               .reject { |c, _| @target.alias?(c) }

        # Group the commands according to their *-suffix
        suffixes = main_commands.each_with_object({}) do |(_, cmd), memo|
          _, suffix = cmd.name.split('-', 2) || '__other__'
          memo[suffix] ||= []
          memo[suffix] << cmd
          memo
        end

        # Group the suffixes into sections
        hash = suffixes.each_with_object({}) do |(suffix, commands), memo|
          key = sections.keys.find { |group| group.include?(suffix) } || ['__other__']
          memo[key] ||= []
          memo[key].push(*commands)
        end

        hash.keys.each do |key|
          # Partition the commands into known/unknown prefixes
          values_postition = hash[key].map do |command|
            prefix, _ = command.name.split('-', 2)
            idx = command_prefix_order.each_with_index.find { |p, _| p == prefix }&.fetch(1)
            [command, idx]
          end
          known, unknown = values_postition.partition { |_, idx| idx }

          # Sort known commands by prefix order and unknown commands alphanumerically
          known.sort_by! { |_, idx| idx }.map! { |c, _| c }
          unknown.map! { |c, _| c }.sort! { |c1, c2| c1.name <=> c2.name }

          # Reform the command order
          hash[key] = [*known, *unknown]
        end
        hash
      end
    end
  end

  class HelpFormatter < Commander::HelpFormatter::Terminal
    PROGRAM_HELP = ERB.new(<<~'RUBY', nil, '-')
<%=
  if !program(:nobanner)
    begin
      require 'openflight/banner'
      OpenFlight::Banner.render(title: program(:application), version: program(:version))
    rescue LoadError
      nil
    end
  end
-%>
  <%= $terminal.color "NAME", :bold %>:

    <%= program :name %>

  <%= $terminal.color "DESCRIPTION", :bold %>:

    <%= Commander::HelpFormatter.indent 4, program(:description) %>

  <%= $terminal.color "COMMANDS", :bold %>:
<% for section, commands in commands_by_section do -%>

    <%= $terminal.color("#{sections[section] || 'Miscellaneous:'}", :bold) %>
<%   for command in commands do -%>
    <%= "%-#{max_command_length}s %s" % [command.name, command.summary || command.description] %>
<%   end -%>
<% end %>
<% unless @aliases.empty? -%>
  <%= $terminal.color "ALIASES", :bold %>:
  <% for alias_name, args in @aliases.sort %>
    <%= "%-#{max_aliases_length}s %s %s" % [alias_name, command(alias_name).name, args.join(' ')] -%>
  <% end %>
<% end %>
<% unless global_slop.options.empty? -%>
  <%= $terminal.color "GLOBAL OPTIONS", :bold %>:
	<% global_slop.options.each do |global| -%>

<% tag = if [Slop::BoolOption, Slop::NullOption]
           nil
         elsif meta = option.config[:meta]
           meta
         else
           option.key.upcase
         end
-%>
    <%= global.flags.join ', ' %> <%= tag %>
        <%= Commander::HelpFormatter.indent 8, global.desc %>
	<% end -%>
<% end -%>
<% if program :help -%>
  <% for title, body in program(:help) %>
  <%= $terminal.color title.to_s.upcase, :bold %>:

    <%= body %>
  <% end -%>
<% end %>
RUBY

    def render
      ctx = ProgramContext.new(@runner)
      PROGRAM_HELP.result(ctx.get_binding)
    end

    # NOTE: Do not override the following methods as they render they render
    # the individual commands
    # def render_command(command)
    #   super
    # end
    #
    # def template(name)
    #   super
    # end
  end
end

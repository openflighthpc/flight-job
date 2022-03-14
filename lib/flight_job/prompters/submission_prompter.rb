#==============================================================================
# Copyright (C) 2022-present Alces Flight Ltd.
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

require 'tty-prompt'
require 'tempfile'

require_relative 'base_prompter'

module FlightJob
  module Prompters
    # Used for interactive submission of scripts.
    #
    # It prompts the user for:
    #
    # 1. Answers to the given questions.
    #
    # NOTE: The questions must be topologically sorted on their dependencies
    # otherwise these prompts will not function correctly
    class SubmissionPrompter < BasePrompter
      SUMMARY = ERB.new(<<~'TEMPLATE', nil, '-')
      <%= pastel.bold.underline 'SUMMARY' %>

      <%= pastel.bold 'Answers:' %>
      <%
          questions.each do |question|
            next unless prompt?(question) -%>
      <%=   question_label(question) -%>
      <%    value = answers[question.id]
            value = question.default if value.nil?
            value = (value.is_a?(Array) ? value.join(',') : value.to_s)
            if value.empty?
      -%>
      <%=     " #{pastel.yellow('(none)')}" %>
      <%    elsif question.format['type'] == 'multiline_text' -%>

      <%      value.each_line do |line| -%>
      <%=       pastel.green(line.chomp) %>
      <%      end -%>
      <%    else -%>
      <%=     " #{pastel.green(value)}" %>
      <%    end -%>
      <%  end -%>
      TEMPLATE
    end
  end
end

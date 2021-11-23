#==============================================================================
## Copyright (C) 2021-present Alces Flight Ltd.
##
## This file is part of Flight Job.
##
## This program and the accompanying materials are made available under
## the terms of the Eclipse Public License 2.0 which is available at
## <https://www.eclipse.org/legal/epl-2.0>, or alternative license
## terms made available by Alces Flight Ltd - please direct inquiries
## about licensing to licensing@alces-flight.com.
##
## Flight Job is distributed in the hope that it will be useful, but
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
## IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
## OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
## PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
## details.
##
## You should have received a copy of the Eclipse Public License 2.0
## along with Flight Job. If not, see:
##
##  https://opensource.org/licenses/EPL-2.0
##
## For more information on Flight Job, please visit:
## https://github.com/openflighthpc/flight-job
##==============================================================================
module FlightJob
  # The following helper is designed to be used by QuestionPrompter to output
  # question descriptions with the correct formatting/styling. It was created
  # when it was judged that questions and their descriptions should be handled
  # separately from the TTY::Prompt that takes the user's input; this meant that
  # questions needed a way of being formatted without TTY::Prompt's help.
  class WrapIndentHelper
    def self.call(description, max=80, indent_level=0)
      # - Split string into an array with one line per element,
      # - Prepend two spaces to the start of each line for each indent level
      # - Join the lines with a newline character and return the result
      wrapped_description = split_string(description, max).map do |s|
        s.prepend("  " * indent_level)
      end

      return wrapped_description.join("\n")
    end

    private

    # Regularly express your desire to split the description into lines of no
    # more than 80 characters, rounding down if the wrap would begin in the
    # middle of a word.
    def self.split_string(str, max)
      return str.scan(/\S.{0,#{max}}\S(?=\s|$)|\S+/)
    end
  end
end

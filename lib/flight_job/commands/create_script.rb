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

require 'json'

module FlightJob
  module Commands
    class CreateScript < Command
      MAX_STDIN_SIZE = 1*1024*024

      def run
        # Locate the template
        template = Template.new(id: args.first)
        unless template.valid?
          FlightJob.logger.debug("Missing/invalid template: #{template}\n") do
            template.errors.full_messages.join("\n")
          end
          raise MissingTemplateError, "Could not locate template: #{template.id}"
        end

        # Render the script
        script = Script.new(template_id: template.id, script_name: template.script_template_name)
        script.render(**answers)

        $stderr.puts "Generated Script: #{script.script_path}"
      end

      def answers
        @answers ||= if opts.stdin
          begin
            # TODO: Validate the correct answers have been provided
            input = $stdin.read_nonblock(MAX_STDIN_SIZE)
            if input.length == MAX_STDIN_SIZE
              raise InputError, "The STDIN exceeds the maximum size of: #{MAX_STDIN_SIZE}B"
            end
            JSON.parse(input)
          rescue Errno::EWOULDBLOCK, Errno::EWOULDBLOCK
            raise InputError, "Failed to read the data from STDIN"
          rescue JSON::ParserError
            raise InputError, 'The STDIN is not valid JSON!'
          end
        else
          # TODO: Implement answering questions
          {}
        end
      end
    end
  end
end

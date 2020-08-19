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

module FlightJob
  module Commands
    class Copy < Command
      def run
        puts File.read(resolve_template.path)
      end

      def resolve_template
        # Finds by ID if there is a single integer argument
        if args.first.match?(/\A\d+\Z/)
          # Corrects for the 1-based numbering
          index = args.first.to_i - 1
          if index < 0 || index >= matcher.templates.length
            raise MissingError, <<~ERROR.chomp
              Could not locate a template with index: #{args.first}
            ERROR
          end
          matcher.templates[index]

        # Handle loose resolution by name
        else
          templates = load_templates_from_args
          if templates.length == 1
            templates.first
          elsif templates.length > 1
            raise MissingError, <<~ERROR.chomp
              Could not uniquely identify a job template. Did you mean one of the following?
              #{Paint[list_output.render(*templates), :reset]}
            ERROR
          else
            raise MissingError, "Could not locate: #{args.join(' ')}"
          end
        end
      end

      def load_templates_from_args
        Template.standardize_string(args.first)
                .split('_')
                .uniq
                .reduce(matcher) { |memo, key| memo.search(key) }
                .templates
      end
    end
  end
end

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
        FileUtils.mkdir_p File.dirname(dst_path)
        FileUtils.cp template.path, dst_path
        $stderr.puts <<~INFO.chomp
          Successfully copied the template to: #{dst_path}
        INFO
      end

      def dst_name
        args.length > 1 ? args[1] : template.name
      end

      def dst_path
        @dst_path ||= begin
          # NOTE: expand_path honours absolute path inputs
          path = File.expand_path(dst_name)

          # Allow copies to a directory with the original filename
          path = File.join(path, template.name) if Dir.exists?(path)

          if File.exists?(path)
            # Identifies the used copy indices
            regex = /(?<=\.)[0-9]+\Z/
            copies = Dir.glob("#{path}\.*")
                        .map { |p| (m = regex.match(p)) ? m[0].to_i : nil }
                        .reject(&:nil?)
                        .sort
            copies.unshift(0)

            # Finds the first unused index
            index = copies.each_with_index
                          .find { |cur, idx| cur + 1 != copies[idx + 1] }
                          .first + 1

            # Appends the path with the index
            "#{path}.#{index}"
          else
            path
          end
        end
      end

      def template
        @template ||= begin
          # Finds by ID if there is a single integer argument
          if args.first.match?(/\A\d+\Z/)
            # Corrects for the 1-based numbering
            index = args.first.to_i - 1
            if index < 0 || index >= templates.length
              raise MissingError, <<~ERROR.chomp
                Could not locate a template with index: #{args.first}
              ERROR
            end
            templates[index]

          # Handles an exact match
          elsif match = templates.find { |t| t.name == args.first }
            match

          else
            # Attempts a did you mean?
            regex = /#{args.first}/
            matches = templates.select { |t| regex.match?(t.name) }
            if matches.empty?
              raise MissingError, "Could not locate: #{args.first}"
            else
              raise MissingError, <<~ERROR.chomp
                Could not locate: #{args.first}. Did you mean one of the following?
                #{Paint[list_output.render(*matches), :reset]}
              ERROR
            end
          end
        end
      end

      def templates
        @templates ||= Template.load_all
      end
    end
  end
end

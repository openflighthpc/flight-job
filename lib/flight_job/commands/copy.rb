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
        FileUtils.cp resolve_template.path, dst_path
        $stderr.puts <<~INFO.chomp
          Successfully copied the template to: #{dst_path}
        INFO
      end

      def src_name
        args.first
      end

      def dst_name
        args.length > 1 ? args[1] : src_name
      end

      def dst_path
        @dst_path ||= begin
          # NOTE: expand_path honours absolute path inputs
          path = File.expand_path(dst_name)

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

      def resolve_template
        # Finds by ID if there is a single integer argument
        if src_name.match?(/\A\d+\Z/)
          # Corrects for the 1-based numbering
          index = src_name.to_i - 1
          if index < 0 || index >= matcher.templates.length
            raise MissingError, <<~ERROR.chomp
              Could not locate a template with index: #{src_name}
            ERROR
          end
          templates[index]

        # Handles an exact match
        elsif template = templates.find { |t| t.name == src_name }
          template

        else
          # Attempts a did you mean?
          regex = /#{src_name}/
          matches = templates.select { |t| regex.match?(t.name) }
          if matches.empty?
            raise MissingError, "Could not locate: #{src_name}"
          else
            raise MissingError, <<~ERROR.chomp
              Could not locate: #{src_name}. Did you mean one of the following?
              #{Paint[list_output.render(*matches), :reset]}
            ERROR
          end
        end
      end

      def load_templates_from_args
        Template.standardize_string(src_name)
                .uniq
                .reduce(matcher) { |memo, key| memo.search(key) }
                .templates
      end

      def templates
        @templates ||= Template.load_all
      end
    end
  end
end

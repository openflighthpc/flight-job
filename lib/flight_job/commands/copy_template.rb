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
    class CopyTemplate < Command
      def run
        # Check for nil defaults before rendering, as a nil working
        # directory raises an error.
        without_defaults = template.without_defaults
        if without_defaults.any?
          $stderr.puts pastel.yellow <<~INFO.chomp
            WARNING: Copied template is missing default values for: #{without_defaults.map(&:id).join(', ')}
          INFO
        end
        content = render_content
        FileUtils.mkdir_p File.dirname(dst_path)
        File.write(dst_path, content)
        $stderr.puts <<~INFO.chomp
          Successfully copied the template to: #{dst_path}
        INFO
      end

      def dst_name
        args.length > 1 ? args[1] : template.script_template_name
      end

      def dst_path
        @dst_path ||= begin
          # NOTE: expand_path honours absolute path inputs
          path = File.expand_path(dst_name)

          # Allow copies to a directory with the original filename
          path = File.join(path, template.script_template_name) if Dir.exists?(path)

          if File.exist?(path)
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
        @template ||= load_template(args.first)
      end

      def render_content
        Script.new(template_id: template.id, script_name: template.script_template_name).renderer.render
      end
    end
  end
end

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

module FlightJob
  module OptionGenerators
    class FileListing
      def initialize(directories:, include_null: false, glob: '*', format_path: 'basename')
        @directories = directories
        @format_path = format_path
        @glob = glob
        @include_null = include_null
      end

      def call
        paths = @directories.reduce([]) do |accum, dir|
          dir = map_placeholders(dir)
          accum += select_entries(dir)
          accum
        end
        case @include_null
        when true
          [ { "text" => "(none)",      "value" => nil } ] + paths
        when String
          [ { "text" => @include_null, "value" => nil } ] + paths
        else
          paths
        end
      end

      private

      def map_placeholders(dir)
        segments = []
        remaining = dir
        loop do
          segments << File.basename(remaining)
          break if remaining == File::SEPARATOR
          remaining = File.dirname(remaining)
        end
        segments = segments
          .reverse
          .map { |segment| sub_placeholder(segment) }
        File.join(*segments)
      end

      def sub_placeholder(segment)
        case segment
        when "<username>"
          Etc.getlogin
        else
          segment
        end
      end

      def select_entries(dir)
        return [] unless File.directory?(dir)
        Dir.glob(File.join(dir, @glob))
          .select { |e| File.file?(e) }
          .map { |e| { "text" => text_for_entry(e, dir), "value" => e } }
      end

      def text_for_entry(e, dir)
        case @format_path
        when 'absolute'
          e
        when 'relative'
          Pathname.new(e).relative_path_from(dir).to_s
        when 'basename'
          File.basename(e)
        else
          File.basename(e)
        end
      end
    end
  end
end

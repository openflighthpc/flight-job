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

    # Substitutes placeholders in path.
    #
    # A place holder has the format `<identifier>` bracketed by the path
    # separator.
    #
    # E.g. if the process is running as the user `vagrant`, the `<username>`
    # placeholder is substituted with the string `vagrant`.
    #
    # PathPlaceholder.new(path: '/some/<username>/dir')
    #=> '/some/vagrant/dir`.
    class PathPlaceholder
      def initialize(path: nil)
        @path = path
      end

      def call
        case @path
        when nil
          nil
        when String
          map_placeholders(@path)
        when Array
          @path.map { |p| map_placeholders(p) }
        end
      end

      private

      def map_placeholders(path)
        segments = []
        remaining = path
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
    end
  end
end

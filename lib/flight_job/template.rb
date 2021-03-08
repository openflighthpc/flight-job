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
  Template = Struct.new(:path) do
    PREFIX_REGEX = /\A(?<prefix>\d+)_(?<rest>.*)\Z/
    METADATA_REGEX = /\A#@\s*flight_JOB\[(?<key>.+)\]\s*:\s*(?<value>.*)\Z/

    ##
    # Helper method for loading in all the templates
    def self.load_all
      Dir.glob(File.join(FlightJob.config.templates_dir, '*'))
         .map { |p| Template.new(p) }
         .sort
         .tap { |guides| guides.each_with_index { |g, i| g.index = i + 1 } }
    end

    attr_reader :prefix, :name
    attr_writer :index

    def initialize(*a)
      super

      # Sets the initial name off the basename
      @name = File.basename(path)

      # Strips the prefix from the name. It is only used for sort order
      if match = PREFIX_REGEX.match(name)
        # Remove the prefix from the name, and trim leading zeros
        @prefix = match.named_captures['prefix'].to_i
        @name = match.named_captures['rest']
      end
    end

    ##
    # Strips the file extension, downcases, and converts `-` to `_` for sorting purposes
    def sort_name
      @sort_name ||= File.basename(name, '.*').gsub('-', '_').downcase
    end

    ##
    # Comparison Operator
    def <=>(other)
      return nil unless self.class == other.class
      if prefix == other.prefix
        sort_name <=> other.sort_name
      elsif prefix && other.prefix
        prefix <=> other.prefix
      elsif prefix
        -1
      else
        1
      end
    end

    ##
    # A template's index depends on the sort order within the greater list of templates
    # To prevent time complexity issues, it is injected onto template after it is loaded
    # This creates two problems:
    #  * It could be accessed before being set, triggering an internal error
    #  * It can become stale and should be viewed with scepticism
    def index
      @index || raise(InternalError, <<~ERROR.chomp)
        The template index has not been set: #{path}
      ERROR
    end

    ##
    # The content of the template file
    def content
      @content = File.read(path)
    end

    ##
    # Loads the flight_JOB metadata from the magic comments
    def metadata
      @metadata = begin
        content.each_line
               .map { |l| METADATA_REGEX.match(l) }
               .reject(&:nil?)
               .each_with_object({}) do |match, memo|
          memo[match.named_captures['key'].to_sym] = match.named_captures['value']
        end.tap do |hash|
          hash[:filename] = name
        end
      end
    end
  end
end

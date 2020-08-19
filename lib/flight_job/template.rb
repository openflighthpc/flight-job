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

    ##
    # Used to convert strings into a standardized format. This provides case
    # and word boundary invariance. The standardization process will:
    # * Use underscore for the word boundaries, and
    # * Downcase all letters
    def self.standardize_string(string)
      string.dup                # Don't modify the input string
            .gsub(/[\s-]/, '_') # Treat hyphen as an underscore
            .downcase           # Make it case insensitive
    end

    ##
    # Helper method for loading in all the templates
    def self.load_all
      Dir.glob(File.join(Config::CACHE.templates_dir, '*'))
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
    # Comparison Operator
    def <=>(other)
      return nil unless self.class == other.class
      if prefix == other.prefix
        name <=> other.name
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
  end
end

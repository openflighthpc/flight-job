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
require_relative 'template'

module FlightJob
  class Matcher
    include Enumerable
    extend  Forwardable

    ##
    # Helper method for loading in all the templates
    def self.load_templates
      Dir.glob(File.join(Config::CACHE.templates_dir, '*'))
         .map { |p| Template.new(p) }
         .sort
         .tap { |guides| guides.each_with_index { |g, i| g.index = i + 1 } }
    end

    ##
    # Enumerates over a set of templates
    attr_reader     :templates
    def_delegators  :templates, :each

    ##
    # Optionally allow a Matcher to be created with a set of templates
    def initialize(templates = nil)
      @templates = templates || self.class.load_templates
    end

    ##
    # Filter the guides by a search key. Note: They key must already be standardized
    def search(key)
      regex = /\A#{key}.*/
      matching = select do |template|
        template.parts.any? { |p| regex.match?(p)  }
      end
      self.class.new(matching)
    end
  end
end

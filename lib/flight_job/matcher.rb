#==============================================================================
# Copyright (C) 2022-present Alces Flight Ltd.
#
# This file is part of Flight Job.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# FlightHowto is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with FlightHowto. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on FlightHowto, please visit:
# https://github.com/openflighthpc/flight-howto
#==============================================================================
module FlightJob
  class Matcher
    attr_reader :filters, :attrs

    def initialize(filters, attrs)
      @filters = filters
      @attrs = attrs
    end

    def matches?
      return true unless filters
      attrs.each_pair do |key, attr|
        if filters[key]
          return false unless pass_filter?(filters[key], attr)
        end
      end
      true
    end

    private

    def pass_filter?(filter, attr)
      filter.split(',')
            .uniq
            .each do |f|
        match = File.fnmatch(standardize_string(f), standardize_string(attr))
        return true if match
      end
      false
    end

    def standardize_string(str)
      str ||= ""
      str.downcase
         .strip
         .gsub(/[\s_]/, '-')
    end
  end
end

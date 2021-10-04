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
  # Fancy ordering algorithm for alphanumeric ids.
  #
  # Some ids (e.g., script ids) are commonly of the form <prefix>-<suffix>.
  # Where prefix is alphanumeric and suffix is numeric.
  #
  # If the given ids meet this criteria we wish to sort them by their prefix
  # alphanumerically and by their suffix numerically.  E.g.,
  #
  # * simple
  # * simple-1
  # * simple-2
  # * simple-10
  # * simple-array
  # * simple-array-1
  # * simple-array-2
  # * simple-array-10
  #
  # Limitation:
  #
  # This is currently limited to numerically sorting on only the last
  # numerical suffix.  E.g.,
  #
  # Actual                Not yet supported
  #                                         
  # `simple-1`            `simple-1`
  # `simple-10`           `simple-1-1`
  # `simple-1-1`          `simple-10`
  # `simple-10-1`         `simple-10-1`
  #
  class FancyIdOrdering
    def self.call(a, b)
      new(a, b).call
    end

    def initialize(a, b)
      @a = a
      @b = b
    end

    def call
      return 0  if @a.nil? && @b.nil?
      return -1 if @a.nil?
      return 1  if @b.nil?
      sort_criteria(@a) <=> sort_criteria(@b)
    end

    private

    def sort_criteria(id)
      regexp = /\A(.*-)(\d+)\Z/
      md = id.match(regexp)
      if md.nil?
        [id]
      else
        [md[1], md[2].to_i]
      end
    end
  end
end

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
  # The following parser is designed to turn JSON:Schema oneOf directive into
  # a psuedo-case statement
  #
  # It requires the 'oneOf' matcher to be specified within as a '$def' and
  # contain a property defined as a 'const':
  #
  # "$def" : {
  #   <def-key> : {
  #     "enum": [<all>, <possible>, <match>, <values>, ...],
  #     "oneOf" : [
  #       "properties" : {
  #         <const-key> : { "const" : <match-value> }
  #
  #       }, ...
  #     ]
  #   }
  # }
  #
  # NOTE: This parser is designed to filter out all the 'oneOf' errors if
  #       there isn't a match on the 'const-key'. The 'enum' error will
  #       catch the condition instead.
  #
  # When JSON:Schema runs, it will generate error for each entry within the
  # 'oneOf' specification. Whilst this is *technically* correct, it generates
  # a lot of red-herrings.
  #
  # This parser processes each error and returns one of the following:
  # * nil -   The error is unrelated to the 'oneOf' match
  # * false - The error failed on the 'oneOf' match but for the incorrect 'const-key'
  # * true -  The error failed on the 'oneOf' with the correct 'const-key'

  OneOfParser = Struct.new(:def_key, :const_key, :errors_array) do
    def flags
      @flags ||= errors_array.map do |error|
        key = error_key(error)
        next nil unless key
        const_indices[key] == error_index(error)
      end
    end

    private

    # Groups the errors according to the data_pointer's "directory"/"parent",
    # if schema_pointer matches the def_regex
    def partitioned_errors
      @partitioned_errors = errors_array.each_with_object({}) do |error, memo|
        next unless def_regex.match?(error["schema_pointer"])
        key = error_key(error)
        next unless key
        memo[key] ||= []
        memo[key] << error
      end
    end

    # Determines the first missing index
    def const_indices
      @const_indices ||= partitioned_errors.map do |key, errors|
        indices = errors.select { |e| const_regex.match? e['schema_pointer'] }
                        .map { |e| error_index(e) }
                        .uniq
                        .sort
        if indices.empty?
          index = 0
        else
          index = (0..(indices.last + 1)).find { |i| indices[i] != i }
        end
        [key, index]
      end.to_h
    end

    def def_regex
      @def_regex ||= Regexp.new(
        File.join('\A/\$defs', def_key, 'oneOf/(?<index>\d+)')
      )
    end

    def const_regex
      @const_regex ||= Regexp.new(
        File.join('\A/\$defs', def_key, 'oneOf/(?<index>\d+)', const_key + '\Z')
      )
    end

    def error_key(error)
      match = def_regex.match(error['schema_pointer'])
      match ? match.to_s : nil
    end

    def error_index(error)
      def_regex.match(error['schema_pointer']).named_captures['index'].to_i
    end
  end
end

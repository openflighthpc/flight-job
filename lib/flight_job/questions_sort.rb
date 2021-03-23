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

require 'tsort'

module FlightJob
  QuestionSort = Struct.new(:hash) do
    # NOTE: This is not a user facing error, instead it is used to flag
    # the missing question ID
    class UnresolvedReference < RuntimeError; end

    include TSort

    def self.build(questions)
      new(questions.map { |q| [q.id, q] }.to_h)
    end

    attr_accessor :questions

    def tsort_each_node(&b)
      hash.values.each(&b)
    end

    def tsort_each_child(question, &b)
      id = hash[question.id].related_question_id
      ids = id.nil? ? [] : [id]
      ids.map do |id|
        if hash.key?(id)
          hash[id]
        else
          raise UnresolvedReference, id
        end
      end.each(&b)
    end
  end
end

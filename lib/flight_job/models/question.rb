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
  class Question < ApplicationModel
    attr_accessor :id, :text, :description, :ask_when, :template
    attr_writer :default, :dynamic_default, :format

    def related_question_id
      return nil unless ask_when
      ask_when['value'].split('.')[1]
    end

    def default
      return @default if @dynamic_default.nil?

      generate(**@dynamic_default) || @default
    end

    def format
      return @format unless @format.key?("dynamic_options")

      f = @format.dup
      dynamic_options = f.delete("dynamic_options")
      f.merge("options" => generate(**dynamic_options))
    end

    def serializable_hash(opts = nil)
      opts ||= {}
      {
        id: id,
        text: text,
        description: description,
        default: default,
        ask_when: ask_when,
        format: format,
      }
        .reject { |k, v| v.nil? }
    end

    private

    def generate(**opts)
      QuestionGenerators.call(**opts.symbolize_keys)
    end
  end
end

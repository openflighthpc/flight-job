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

require 'ostruct'

module FlightJob
  # This object is used to provide nice answer handling for missing questions so that:
  # questions.missing.answer # => nil (Instead of raising NoMethodError)
  #
  # It essentially reimplements the OpenStruct initializer to support defaults handling
  # in a similar manner to Hash.
  #
  # The key? method must always return 'true' to denote that the OpenStruct responds
  # to all keys. Changing this has undefined behaviour
  #
  # Consider refactoring
  #
  # For full details see:
  # https://github.com/openflighthpc/flight-job/pull/3#discussion_r597600201
  class DefaultsOpenStruct < OpenStruct
    def initialize(opts = {}, &b)
      if b
        @table = Hash.new(&b)
      else
        @table = {}
      end
      @table.define_singleton_method(:key?) { |_| true }
      opts.each do |k, v|
        @table[k.to_sym] = v
      end
    end
  end

  class Renderer
    class AnswerDecorator
      def initialize(question:, answer:)
        @question = question
        @answer = answer
      end

      def answer
        @answer || @question.default
      end

      def default
        @question.default
      end
    end

    class RenderDecorator
      def initialize(template:, answers:)
        @template = template
        @answers = answers
      end

      def question
        questions
      end

      def questions
        @questions ||= begin
          questions = @template.generation_questions.reduce({}) do |memo, question|
            memo.merge({
              question.id => AnswerDecorator.new(question: question,
                                                 answer: @answers[question.id])
            })
          end
          DefaultsOpenStruct.new(questions) do |h, k|
            question = Question.new(id: k)
            h[k] = AnswerDecorator.new(question: question, answer: nil)
          end
        end
      end
    end

    def initialize(template:, answers:)
      @template = template
      @answers = answers
    end

    def render
      [render_directives, render_adapter, render_workload].reject(&:blank?).join("\n")
    end

    def render_workload
      ERB.new(File.read(@template.workload_path), nil, '-').result(generate_binding)
    end

    private

    def render_adapter
      # NOTE: The adapter is designed augment the directives,
      # monolithic templates without directives can not benefit from the adapter
      return nil unless File.exists? @template.directives_path
      ERB.new(File.read(Flight.config.adapter_script_path), nil, '-').result(generate_binding)
    end

    def render_directives
      return nil unless File.exists? @template.directives_path
      ERB.new(File.read(@template.directives_path), nil, '-').result(generate_binding)
    end

    def generate_binding
      RenderDecorator.new(template: @template, answers: @answers).instance_exec { binding }
    end
  end
end

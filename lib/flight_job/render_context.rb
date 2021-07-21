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

# Ensure time is available for the templates
require 'time'

module FlightJob
  class RenderError < GeneralError; end

  class RenderContext
    class AnswerDecorator
      def initialize(question:, answer:)
        @question = question
        @answer = answer
      end

      def answer
        @answer || @question.default
      end

      # Converts slurm times into seconds. This allows questions to use Slurm's
      # time specification and convert it into something a different standard.
      #
      # Supports:
      # * MM
      # * MM:SS
      # * HH:MM:SS
      # * DD-HH
      # * DD-HH:MM
      # * DD-HH:MM:SS
      #
      # XXX: This time format is needlessly verbose! In practice, users will
      # not be specifying times down to the second.
      #
      # It also means the \d\d:\d\d is sometimes MM:SS instead of HH:MM. Both
      # versions are used in question's which is unwieldy to use. Instead the
      # time format should *probably* be simplified to:
      # * MM
      # * HH:MM
      # * DD-HH:MM
      # * DD-HH:MM:SS (maybe?)
      #
      # This does break the standard with slurm, however flight-job is intended
      # to work with other schedulers. It should be a fairly easy to document
      # the slimmed down standard.
      #
      # This does mean that each scheduler will need to define a helper method
      # that can convert the time to the appropriate format, but this should
      # be relatively straight forward.
      def answer_in_seconds
        case answer
        when Integer
          answer
        when /\A\d+\Z/
          answer.to_i * 60
        when /\A\d+:\d+\Z/
          m,s = answer.split(':')
          m.to_i * 60 + s.to_i
        when /\A\d+:\d+:\d+\Z/
          h,m,s = answer.split(':')
          h.to_i * 3600 + m.to_i * 60 + s.to_i
        when /\A\d+-\d+\Z/
          d,h = answer.split('-')
          d.to_i * 86400 + h.to_i * 3600
        when /\A\d+-\d+:\d+\Z/
          d,r = answer.split('-')
          h,m = r.split(":")
          d.to_i * 86400 + h.to_i * 3600 + m.to_i * 60
        when /\A\d+-\d+:\d+:\d+\Z/
          d,r = answer.split('-')
          h,m,s = r.split(":")
          d.to_i * 86400 + h.to_i * 3600 + m.to_i * 60 + s.to_i
        else
          raise RenderError, "Failed to convert time: #{answer}"
        end
      end

      def default
        @question.default
      end
    end

    def initialize(template:, answers:)
      @template = template
      @answers = answers
    end

    # NOTE: The following is unlikely to be required by other schedulers
    # apart from slurm. Consider extracting to a module that is dynamically
    # loaded into the name-space
    def convert_to_slurm_time(remaining)
      day =       remaining % 86400
      remaining = remaining / 86400
      hours =     remaining % 3600
      remaining = remaining / 3600
      minutes =   remaining % 60
      seconds =   remaining / 60
      "#{day}-#{hours}:#{minutes}:#{seconds}"
    end

    def render
      @template.to_erb.result(binding)
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
end

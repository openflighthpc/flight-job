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

require 'tty-prompt'

module FlightJob
  module Commands
    class CreateScript < Command
      def run
        questions = request_template_questions(args.first)
        raise_unsupported unless questions.all?(&:supported?)
        questions = QuestionSort.build(questions).tsort

        answers = questions.each_with_object({}) do |question, memo|
          if question.related_question_id
            related = memo[question.related_question_id]
            unless related == question.askWhen['eq']
              Config::CACHE.logger.debug("Skipping question: #{question.id}")
              next
            end
          end

          memo[question.id] = case question.format['type']
          when 'text'
            prompt.ask(question.text, default: question.default)
          when  'multiline_text'
            # NOTE: The 'default' field does not work particularly well for multiline inputs
            # Consider replacing with $EDITOR
            lines = prompt.multiline(question.text)
            lines.empty? ? question.default : lines.join('')
          when 'select'
            opts = {}
            choices = question.format['options'].each_with_index.map do |opt, idx|
              opts[:default] = idx + 1 if opt['value'] == question.default
              { name: opt['text'], value: opt['value'] }
            end
            prompt.select(question.text, choices, **opts)
          else
            raise InternalError, "Unexpectedly reached question type: #{question.format['type']}"
          end
        end
        puts answers
      end

      def raise_unsupported
        raise UnsupportedError, <<~ERROR.chomp
          The selected template format is not currently supported.
          Please contact your system administrator for further assistance.
        ERROR
      end

      def prompt
        @prompt = TTY::Prompt.new
      end
    end

    QuestionSort = Struct.new(:hash) do
      include TSort

      def self.build(questions)
        new(questions.map { |q| [q.id, q] }.to_h)
      end

      attr_accessor :questions

      def tsort
        super
      rescue TSort::Cyclic
        raise UnsupportedError, <<~ERROR.chomp
          Failed to resolve the templates question order.
          Please contact your system administrator for further assistence.
        ERROR
      end

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
            raise UnsupportedError, <<~ERROR.chomp
              Could not locate question: #{id}
              Please contact your system administrator for further assistence.
            ERROR
          end
        end.each(&b)
      end
    end
  end
end

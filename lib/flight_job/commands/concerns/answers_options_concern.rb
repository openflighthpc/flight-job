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

require 'json'

module FlightJob
  module Commands
    module Concerns
      # Common code for extracting answers form the CLI options and arguments.
      module AnswersOptionsConcern
        VALIDATION_ERROR = ERB.new(<<~'TEMPLATE', nil, '-')
          Cannot continue as the following errors occurred whilst validating the answers
          <% errors.each do |key, msgs| -%>
          <%   next if msgs.empty? -%>

          <%= key == :root ? "The root value" : "'" + key + "'" -%> is invalid as it:
          <%   msgs.each do |msg| -%>
          <%= ::FlightJob::Prompters::SubmissionPrompter.bulletify(msg) %>
          <%   end -%>
          <% end -%>
        TEMPLATE

        private

        def answers_provided?
          !answers.nil?
        end

        def answers_provided_on_stdin?
          if opts.stdin
            true
          elsif opts.answers
            stdin_flag?(opts.answers)
          else
            false
          end
        end

        def answers
          return unless opts.stdin || opts.answers
          string = if answers_provided_on_stdin?
                     cached_stdin
                   elsif opts.answers[0] == '@'
                     read_file(opts.answers[1..])
                   else
                     opts.answers
                   end
          JSON.parse(string).tap do |hash|
            # Inject the defaults if possible
            if hash.is_a?(Hash)
              questions.each do |question|
                next if question.default.nil?
                next if hash.key? question.id
                hash[question.id] = question.default
              end
            end

            # Validate the answers
            errors = validate_answers(hash)
            next if errors.all? { |_, msgs| msgs.empty? }

            # Raise the validation error
            bind = OpenStruct.new(errors).instance_exec { binding }
            msg = VALIDATION_ERROR.result(bind)
            raise InputError, msg.chomp
          end
        rescue JSON::ParserError
          raise InputError, <<~ERROR.chomp
          Failed to parse the answers as they are not valid JSON:
          #{$!.message}
          ERROR
        end

        # Validate that user-provided answers.
        def validate_answers(hash)
          raise NotImplementedError
        end

        # Return the list of `Question`s that are being asked.
        def questions
          raise NotImplementedError
        end
      end
    end
  end
end

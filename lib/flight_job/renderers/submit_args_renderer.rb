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

require_relative 'base_renderer'

module FlightJob
  module Renderers

    # Render the answers to the submission time questions using the given ERb
    # template.
    class SubmitArgsRenderer
      class RenderDecorator < BaseRenderer::RenderDecorator
      end

      def initialize(answers:, questions:, template_path:)
        @answers = answers
        @questions = questions
        @template_path = template_path
      end

      def render
        template = File.read(@template_path)
        ERB.new(template, nil, '-').result(generate_binding)
      end

      private

      def generate_binding
        decorator = RenderDecorator.new(answers: @answers, questions: @questions)
        decorator.instance_exec { binding }
      end
    end
  end
end

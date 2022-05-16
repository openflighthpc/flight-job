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

require_relative 'base_renderer'

module FlightJob
  module Renderers
    class ScriptRenderer
      class TemplateDecorator
        def initialize(template)
          @template = template
        end

        def tag(name)
          tag = @template.tags.detect { |t| t.split('=')[0] == name}
          return nil if tag.nil?
          tag.split('=')[1]
        end
      end

      class RenderDecorator < BaseRenderer::RenderDecorator
        def initialize(template:, answers:, questions:)
          @template = template
          super
        end

        def template
          @template_decorator ||= TemplateDecorator.new(@template)
        end
      end

      def initialize(template:, answers:)
        @template = template
        @answers = answers
      end

      def render
        [render_directives, render_adapter, render_workload].reject(&:blank?).join("\n")
      end

      private

      def render_workload
        ERB.new(File.read(@template.workload_path), trim_mode: '-').result(generate_binding)
      end

      def render_adapter
        # NOTE: The adapter is designed to augment the directives. Monolithic
        # 'script templates' (sans 'directives template') cannot benefit from the adapter
        return nil unless File.exist? @template.directives_path
        ERB.new(File.read(Flight.config.adapter_script_path), trim_mode: '-').result(generate_binding)
      end

      def render_directives
        return nil unless File.exist? @template.directives_path
        ERB.new(File.read(@template.directives_path), trim_mode: '-').result(generate_binding)
      end

      def generate_binding
        decorator = RenderDecorator.new(
          template: @template,
          answers: @answers,
          questions: @template.generation_questions
        )
        decorator.instance_exec { binding }
      end
    end
  end
end

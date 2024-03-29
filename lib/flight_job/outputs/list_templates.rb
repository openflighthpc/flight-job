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

require 'output_mode'

module FlightJob
  class Outputs::ListTemplates < OutputMode::Formatters::Index
    # Override "render" method to add invalid template footnote
    def render(*a, **o)
      super.tap do |txt|
        next unless humanize?
        next unless @invalid_template
        txt << "\n"
        txt << pastel.yellow(" * Invalid template")
      end
    end

    def register_all
      register_index
      register_id
      if humanize? 
        register_name
        register_file if verbose?
      else
        register_file
        register_name
      end
    end

    def pastel
      @pastel ||= Pastel.new(enabled: color?)
    end

    private

    def register_index
      register(header: 'Index', row_color: :yellow) do |template|
        template.index
      end
    end

    def register_id
      register(header: 'ID') do |template|
        if template.errors.any?
          @invalid_template = true
          pastel.yellow "#{template.id}*"
        else
          template.id
        end
      end
    end

    def register_name
      register(header: 'Name') do |template|
        template.name
      end
    end
    
    def register_file
      file_header = "File (Dir: #{FlightJob.config.templates_dir})"
      register(header: file_header) do |template|
        if humanize?
          Pathname.new(template.workload_path).relative_path_from FlightJob.config.templates_dir
        else
          template.workload_path
        end
      end
    end
  end
end


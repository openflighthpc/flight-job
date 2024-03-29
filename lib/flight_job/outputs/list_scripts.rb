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
  class Outputs::ListScripts < OutputMode::Formatters::Index
    def render(*a, **o)
      super.tap do |txt|
        next unless humanize?
        next unless @invalid_script
        txt << "\n"
        txt << pastel.red(" * Invalid script")
      end
    end

    def register_all
      register_id
      register(header: 'Template ID') { |s| s.template_id }
      register(header: 'File Name') { |s| s.script_name }

      register(header: 'Created at') do |script|
        Time.parse script.created_at if script.created_at
      end

      if verbose?
        register(header: 'Path') { |s| s.script_path }
      end
    end

    def register_id
      register(header: 'ID', row_color: :yellow) do |script|
        if script.valid?
          script.id
        else
          @invalid_script = true
          pastel.red "#{script.id}*"
        end
      end
    end

    def pastel
      @pastel ||= Pastel.new(enabled: color?)
    end
  end
end

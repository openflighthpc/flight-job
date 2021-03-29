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

require 'tty-editor'

module FlightJob
  class Commands::EditScript < Command
    def run
      # Ensure the script exists up front
      script

      # Opens vimish commands with the start line at the top of the editor,
      # Other common editors will open somewhere near the start line
      # NOTE: gedit needs x-forwarding over ssh, but it also supports the +line
      cmd = if ! start_line
              editor
            elsif ['vim', 'nvim'].include?(editor)
              "#{editor} +#{start_line} -c 'normal! kztj'"
            elsif ['vi', 'emacs', 'nano', 'gedit'].include?(editor)
              "#{editor} +#{start_line}"
            else
              editor
            end

      # Open the file
      TTY::Editor.open(script.script_path, command: cmd)
    end

    def script
      @script ||= load_script(args.first)
    end

    # Determine which line to open the script on
    def start_line
      File.open(script.script_path) do |file|
        _, idx = file.each_line.each_with_index.find do |line, _|
          /^# *>{4,}.*WORKLOAD/.match?(line)
        end
        return idx ? idx + 1 : nil
      end
    end

    def editor
      @editor ||= TTY::Editor.from_env.first || begin
      $stderr.puts pastel.red <<~WARN.chomp
          Defaulting to 'vi' as the editor.
          This can be changed by setting the EDITOR environment variable.
        WARN
        'vi'
      end
    end
  end
end

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
  module Commands
    class EditScriptNotes < Command
      def run
        # Ensure the script exists up front
        script = load_script(args.first)

        if stdin_flag?(opts.notes)
          # Update the notes from stdin
          script.notes.save(cached_stdin)

        elsif opts.notes && opts.notes[0] == '@'
          # Update the notes from a file
          script.notes.save(read_file(opts.notes[1..]))

        elsif opts.notes
          # Update the notes from the CLI
          script.notes.save(opts.notes)

        else
          # Open the notes in the editor
          new_editor.open(script.notes.path)
        end
      end
    end
  end
end

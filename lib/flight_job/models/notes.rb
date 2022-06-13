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
module FlightJob
  class Script < ApplicationModel
    class Notes
      def initialize(script_id, notes = '')
        @script_id = script_id
        @notes = notes
      end

      def load
        Notes.new(@script_id, File.exist?(path) ? File.read(path) : '')
      end

      def read
        @notes || ''
      end

      def save(notes = nil)
        @notes = notes if notes
        File.write path, notes || @notes || ''
        FileUtils.chmod(0600, path)
      end

      def path
        @path ||= File.join(FlightJob.config.scripts_dir, @script_id, 'notes.md')
      end
    end
  end
end

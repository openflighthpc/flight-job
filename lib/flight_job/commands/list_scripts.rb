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

module FlightJob
  module Commands
    class ListScripts < Command
      def run
        if scripts.empty? && !opts.json
          $stderr.puts 'Nothing To Display'
        else
          puts render_output(Outputs::ListScripts, scripts)
        end
      end

      def scripts
        @scripts ||=
          begin
            scripts = Script.load_all(opts)
            if opts.json
              # Prevent invalid scripts from reaching the webapp.  Not ideal,
              # but a decent workaround until the webapp can be updated.
              scripts.reject { |s| !s.errors.empty? }
            else
              scripts
            end
          end
      end
    end
  end
end

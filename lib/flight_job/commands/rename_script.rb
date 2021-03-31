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
    class RenameScript < Command
      def run
        if args[1].length > FlightJob.config.maximum_id_length
          raise InputError,
            "The new id '#{args[1]}' exceeds the maximum length of #{FlightJob.config.maximum_id_length}"
        end
        unless Script::ID_REGEX.match?(args[1])
          raise InputError, "The new id '#{args[1]}' is invalid. It must be alphanumeric but may include dot, hyphen, and underscore: -_."
        end

        # Loads the existing script
        script = load_script(args.first)

        # Attempt to reserve the new script
        unless Script.reserve_public_id(args[1])
          raise InputError, <<~ERROR.chomp
            Failed to rename '#{args[1]}' as it is already in used.
          ERROR
        end

        # Move the public_id file into its new location
        old_path = script.public_id_path
        script.public_id = args[1]
        new_path = script.public_id_path
        FileUtils.mv old_path, new_path

        # Emit the new info
        puts Outputs::InfoScript.build_output(**output_options).render(script)
      end
    end
  end
end

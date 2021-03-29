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
        # Loads the existing script
        script = load_script(args.first)

        # Attempt to reserve the new script
        reservation = Script.new(reserve_id: args[1])
        if reservation.exists?
          raise DuplicateError, "The script '#{reservation.public_id}' already exists!"
        elsif ! reservation.reserved?
          raise InternalError, <<~ERROR
            Unexpectedly failed to rename '#{reservation.public_id}', please try again.
            If this error persists, please contact your system administrator.
          ERROR
        end

        # Generate a list of files to be moved:
        # * The reservation file should not be copied as it coupled to the original names,
        # * The metadata should be copied last to denote it as successful
        files = Dir.glob(File.join(File.dirname(script.metadata_path), '*'))
        files.delete script.reservation_path
        files.delete script.metadata_path
        files.push script.metadata_path

        # Copy the files over, maintaining the original version (temporarily)
        dir = File.dirname(reservation.metadata_path)
        files.each { |p| FileUtils.cp p, dir }

        # Ensure the new script is valid
        new_script = Script.new(id: reservation.public_id)
        unless new_script.valid?
          # XXX: Should the copy be deleted?
          raise InternalError, 'Unexpectedly failed to move the script'
        end

        # Remove the original script and the reservation
        FileUtils.rm_rf File.dirname(script.metadata_path)
        FileUtils.rm reservation.reservation_path

        # Emit the new info
        puts Outputs::InfoScript.build_output(**output_options).render(new_script)
      end
    end
  end
end

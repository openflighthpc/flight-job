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
require_relative "../metadata/base_metadata"

module FlightJob
  class Job < ApplicationModel
    # Broken metadata objects are created when loading invalid jobs. Checks the
    # information available about the jobs is in a suitable format for display.
    # This is currently limited to checking the script_id and scheduler_id.
    class BrokenMetadata < FlightJob::Metadata::BaseMetadata

      attributes(*Metadata.attribute_names)

      def state
        "BROKEN"
      end

      %w(script_id scheduler_id).each do |att|
            define_method(att) do
              value = @parent.send(att)
              return value if value.is_a?(Integer) || value.is_a?(String)
            end
      end
    end
  end
end

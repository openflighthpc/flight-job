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
#require_relative "validator"

module FlightJob
  class Script < ApplicationModel
    # Encapsulates a script's `metadata.yaml` file.
    #
    # * Loads and saves the file.
    # * Validates against a schema.
    # * Provides "atomic"(-ish) updates.
    class Metadata < Metadata::BaseMetadata

      attributes \
        :created_at,
        :tags,
        :template_id,
        :script_name

      attribute :answers, default: {}

      def self.from_template(script)
        initial_metadata = {
          "created_at" => Time.now.rfc3339,
          "tags" => "X",
          "template_id" => "X",
          "script_name" => script.script_name
        }
        path = File.join(script.metadata_path, "metadata.yaml")
        new(initial_metadata, path, script)
      end

      def created_at
        metadata["created_at"]
      end

    end
  end
end

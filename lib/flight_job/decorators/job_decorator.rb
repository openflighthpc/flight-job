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

require 'draper'

module FlightJob
  module Decorators
    class JobDecorator < Draper::Decorator
      include ActiveModel::Serializers::JSON

      # TODO: Port all the methods and remove this delegator
      delegate_all

      def serializable_hash(opts = nil)
        opts ||= {}
        {
          "id" => id,
          "actual_start_time" => actual_start_time,
          "estimated_start_time" => estimated_start_time,
          "actual_end_time" => actual_end_time,
          "estimated_end_time" => estimated_end_time,
          "controls" => controls_dir.serializable_hash,
        }.merge(metadata).tap do |hash|
          # NOTE: The API uses the 'size' attributes as a proxy check to exists/readability
          #       as well as getting the size. Non-readable stdout/stderr would be
          #       unusual, and can be ignored
          hash["stdout_size"] = File.size(stdout_path) if stdout_readable?
          hash["stderr_size"] = File.size(stderr_path) if stderr_readable?

          if Flight.config.includes.include? 'script'
            hash['script'] = load_script
          end

          # Always serialize the result_files
          if results_dir && Dir.exist?(results_dir)
            files =  Dir.glob(File.join(results_dir, '**/*'))
                        .map { |p| Pathname.new(p) }
                        .reject(&:directory?)
                        .select(&:readable?) # These would be unusual and should be rejected
                        .map { |p| { file: p.to_s, size: p.size } }
            hash['result_files'] = files
          else
            hash['result_files'] = nil
          end
        end
      end
    end
  end
end

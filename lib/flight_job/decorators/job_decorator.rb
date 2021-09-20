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
  module Decorators
    class JobDecorator
      include ActiveModel::Serializers::JSON

      def self.delegate_metadata(*keys)
        keys.each do |key|
          define_method(key) { object.metadata[key.to_s] }
        end
      end

      attr_reader :object

      def initialize(object)
        @object = object
      end

      delegate :id, to: :object
      delegate_metadata :script_id, :start_time, :end_time, :scheduler_id, :scheduler_state,
        :stdout_path, :stderr_path, :results_dir, :reason, :created_at, :state,
        :submit_status, :submit_stdout, :submit_stderr

      def actual_start_time
        return nil if Job::STATES_LOOKUP[state] == :pending
        start_time
      end

      def estimated_start_time
        return nil unless Job::STATES_LOOKUP[state] == :pending
        start_time
      end

      def actual_end_time
        return nil unless Job::STATES_LOOKUP[state] == :terminal
        end_time
      end

      def estimated_end_time
        return nil if Job::STATES_LOOKUP[state] == :terminal
        end_time
      end

      def desktop_id
        object.controls_file('flight_desktop_id').read
      end

      def serializable_hash(opts = nil)
        opts ||= {}
        {
          # ----------------------------------------------------------------------------
          # Required - Must not be nil
          #          - Empty string maybe acceptable depending on the attribute
          # ----------------------------------------------------------------------------
          "id" => id,
          "created_at" => created_at,
          "script_id" => script_id,
          "state" => state,
          "submit_status" => submit_status,
          "submit_stdout" => submit_stdout,
          "submit_stderr" => submit_stderr,
          # ----------------------------------------------------------------------------
          # Optional - Maybe nil
          # ----------------------------------------------------------------------------
          "end_time" => end_time,
          "scheduler_id" => scheduler_id,
          "scheduler_state" => scheduler_state,
          "start_time" => start_time,
          "stdout_path" => stdout_path,
          "stderr_path" => stderr_path,
          "results_dir" => results_dir,
          "reason" => reason,
          "actual_start_time" => actual_start_time,
          "estimated_start_time" => estimated_start_time,
          "actual_end_time" => actual_end_time,
          "estimated_end_time" => estimated_end_time,
          "controls" => object.controls_dir.serializable_hash,
        }.tap do |hash|
          # NOTE: The API uses the 'size' attributes as a proxy check to exists/readability
          #       as well as getting the size. Non-readable stdout/stderr would be
          #       unusual, and can be ignored
          hash["stdout_size"] = File.size(stdout_path) if object.stdout_readable?
          hash["stderr_size"] = File.size(stderr_path) if object.stderr_readable?

          if Flight.config.includes.include? 'script'
            hash['script'] = object.load_script
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

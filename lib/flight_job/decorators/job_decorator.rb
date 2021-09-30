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
        if object.job_type == 'SUBMITTING'
          raise InternalError, "Can not decorate an SUBMITTING job"
        end
      end

      delegate :id, :job_type, to: :object
      delegate_metadata :script_id, :scheduler_id, :scheduler_state,
        :stdout_path, :stderr_path, :results_dir, :reason, :created_at,
        :submit_status, :submit_stdout, :submit_stderr, :estimated_start_time, :estimated_end_time

      def state
        case job_type
        when 'FAILED_SUBMISSION'
          'FAILED'
        when 'SINGLETON'
          object.metadata['state']
        when 'ARRAY'
          states = Dir.glob(Task.state_index_path(id, '*', '*'))
                      .map { |p| File.basename(p).split('.').first }
                      .uniq
          if states.include?('RUNNING')
            'RUNNING'
          elsif states.include?('PENDING')
            'PENDING'
          elsif states.include?('CANCELLED')
            'CANCELLED'
          elsif object.metadata['lazy']
            'HOLD'
          elsif states == ['COMPLETED']
            'COMPLETED'
          else
            'FAILED'
          end
        end
      end

      def actual_start_time
        case job_type
        when 'SINGLETON'
          object.metadata['start_time']
        when 'ARRAY'
          # NOTE: Assumes the "first" index actually started first
          # Revisit if required
          (first_task&.metadata || {})['start_time']
        end
      end

      def estimated_start_time
        case job_type
        when 'SINGLETON'
          object.metadata['estimated_start_time']
        when 'ARRAY'
          if actual_start_time
            nil
          else
            # Assumes the first pending job will start first and thus have the estimated time
            # TODO: Augment with metadata version
            (first_pending_task&.metadata || {})['estimated_start_time']
          end
        end
      end

      def actual_end_time
        case job_type
        when 'SINGLETON'
          object.metadata['actual_end_time']
        when 'ARRAY'
          if last_non_terminal_task
            # NOOP
          else
            (last_end_time_task&.metadata || {})['end_time']
          end
        end
      end

      def estimated_end_time
        case job_type
        when 'SINGLETON'
          object.metadata['estimated_end_time']
        when 'ARRAY'
          # Assumes the last non terminal task will be the last to finish
          # TODO: Augment with metadata version
          (last_non_terminal_task&.metadata ||{})['estimated_end_time']
        end
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
          "job_type" => job_type,
          "id" => id,
          "created_at" => created_at,
          "script_id" => script_id,
          "state" => state,
          "submit_status" => submit_status,
          "submit_stdout" => submit_stdout,
          "submit_stderr" => submit_stderr,
          # ----------------------------------------------------------------------------
          # Optional - Maybe nil
          #
          # NOTE: Original start_time/end_time could have been either actual/estimated
          # However the start_time/end_time metadata keys are always the actual time
          #
          # The original behaviour is being maintained in the serialization
          # ----------------------------------------------------------------------------
          "end_time" => actual_end_time || estimated_end_time,
          "scheduler_id" => scheduler_id,
          "scheduler_state" => scheduler_state,
          "start_time" => actual_start_time || estimated_start_time,
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

      private

      def first_task
        @first_task = Task.load_first(id) || false if @first_task.nil?
        @first_task ? @first_task : nil
      end

      def first_pending_task
        @first_pending_task = Task.load_first_pending(id) || false if @first_pending_task.nil?
        @first_pending_task ? @first_pending_task : nil
      end

      def last_non_terminal_task
        @last_non_terminal_task = Task.load_last_non_terminal(id) || false if @last_non_terminal_task.nil?
        @last_non_terminal_task ? @last_non_terminal_task : nil
      end

      def last_end_time_task
        @last_end_time_task = Task.load_last_end_time(id) || false if @last_end_time_task.nil?
        @last_end_time_task ? @last_end_time_task : nil
      end
    end
  end
end

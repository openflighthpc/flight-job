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

require 'json'
require 'json_schemer'

module FlightJob
  class Task < ApplicationModel
    STATES = Job::STATES

    # Tasks have a deliberately *similar* metadata syntax to SINGLETON jobs
    # Proceed with caution before introducing a deviation
    SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => [
        "version", 'state', "scheduler_state"
      ],
      "properties" => {
        # Required
        "version" => { "const" => 1 },
        "scheduler_id" => { "type" => "string", "minLength" => 1 },
        "scheduler_state" => { "type" => "string", "minLength" => 1 },
        "state" => { "enum" => STATES },
        # Optional
        #
        # NOTE: The transient dependency between 'state' and times
        # are enforced by the monitor scripts.
        #
        # It is assumed they metadata will not be edited manually,
        # and thus will remain accurate.
        "estimated_start_time" => { "type" => ['date-time', 'null'] },
        "estimated_end_time" => { "type" => ['date-time', 'null'] },
        "start_time" => { "type" => ["date-time", "null"] },
        "end_time" => { "type" => ["date-time", "null"] },
        "reason" => { "type" => ["string", "null"] },
        # Optional - Non empty
        "stdout_path" => { "type" => "string", "minLength" => 1 },
        "stderr_path" => { "type" => "string", "minLength" => 1 }
      }
    })

    # The job_id/task_index is stored within the metadata_path,
    # and must be injected onto the object
    attr_accessor :job_id, :index
    validates :job_id, presence: true
    validates :index, presence: true

    validate on: [:load, :save_metadata] do
      # Run the initial schema, followed by the specific one
      schema_errors = SCHEMA.validate(metadata).to_a

      # Add the schema errors if any
      unless schema_errors.empty?
        FlightJob.logger.debug("The following metadata file is invalid: #{metadata_path}\n") do
          JSON.pretty_generate(schema_errors)
        end
        errors.add(:metadata, 'is invalid')
      end
    end

    # Reform the state index file on load
    validate on: :load do
      next unless metadata.is_a? Hash
      state = metadata['state']
      next unless STATES.include? state
      reform_state_index_file
    end

    # Reform the end_time index file on load
    validate on: :load do
      next unless metadata.is_a? Hash
      reform_state_index_file
    end

    def self.load_job_tasks(job_id)
      Dir.glob(new(job_id: job_id, index: '*').metadata_path).map do |path|
        index = File.basename(path).split('.')[1]
        self.load(job_id, index)
      end.sort_by { |t| t.index.to_i }
    end

    def self.load(job_id, index)
      new(job_id: job_id, index: index).tap do |task|
        unless File.exist? task.metadata_path
          raise MissingError, "Could not locate task: #{task.tag}"
        end
        unless task.valid?(:load)
          FlightJob.logger.error("Failed to load task: #{task.tag}\n") do
            task.errors.full_messages
          end
          raise InternalError, "Unexpectedly failed to load task: #{task.tag}"
        end
      end
    end

    def self.load_first(job_id)
      index = task_indices(job_id).first
      return nil unless index
      self.load(job_id, index)
    end

    def self.load_first_pending(job_id)
      index = Dir.glob(state_index_path(job_id, '*', 'PENDING'))
                 .map { |p| File.extname(p).sub(/\A\./, '').to_i }
                 .sort.first
      return nil unless index
      self.load(job_id, index)
    end

    def self.load_last_non_terminal(job_id)
      paths = Job::NON_TERMINAL_STATES.reduce([]) do |memo, state|
        new_paths = Dir.glob(state_index_path(job_id, '*', state))
        [*memo, *new_paths]
      end
      index = paths.map { |path| File.extname(path).sub(/\A\./, '').to_i }.sort.last
      return nil unless index
      self.load(job_id, index)
    end

    def self.load_last_end_time(job_id)
      index = Dir.glob(end_time_index_path(job_id, '*', '*'))
                 .map { |p| File.basename(p).split('.', 2) }
                 .sort_by { |t, _| t.to_i }
                 .last&.last
      return nil unless index
      self.load(job_id, index)
    end

    def self.state_index_path(job_id, index, state)
      File.join(FlightJob.config.jobs_dir, job_id, 'states', "#{state}.#{index}")
    end

    def self.end_time_index_path(job_id, index, time)
      if time == '*'
        epoch_time = '*' # Allow globs
      else
        epoch_time = Time.parse(time).to_i
      end
      File.join(FlightJob.config.jobs_dir, job_id, 'terminated', "#{epoch_time}.#{index}")
    end

    private_class_method

    def self.task_indices(job_id)
      Dir.glob(new(job_id: job_id, index: '*').metadata_path).map do |path|
        name = File.basename(path)
        re = /\Ametadata\.(?<index>\d+)\.yaml\Z/
        md = re.match(name)
        md.nil? ? nil : md.named_captures['index'].to_i
      end.sort
    end

    def tag
      "#{job_id}.#{index}"
    end

    def metadata_path
      @metadata_path ||= File.join(task_dir, "metadata.#{index}.yaml")
    end

    def metadata
      @metadata ||= if File.exist? metadata_path
        YAML.load File.read(metadata_path)
      else
        { "version" => 1 }
      end
    end

    def save_metadata(validate: true)
      if validate && !valid?(:save_metadata)
        FlightJob.logger.error("Failed to save task metadata: #{tag}")
        FlightJob.logger.info(errors.full_messages.join("\n"))
        raise InternalError, "Unexpectedly failed to save task '#{tag}' metadata"
      else
        FileUtils.mkdir_p File.dirname(metadata_path)
        File.write metadata_path, YAML.dump(metadata)
        reform_state_index_file
        reform_end_time_index_file
      end
    end

    def scheduler_id
      metadata['scheduler_id']
    end

    def job
      @job ||= Job.new(id: job_id).tap do |j|
        unless j.valid?
          FlightJob.logger.error("Failed to load job: #{job_id}\n") do
            j.errors.full_messages
          end
          raise InternalError, "Unexpectedly failed to load job: #{job_id}"
        end
      end
    end

    def serializable_hash(*_)
      metadata.dup.tap { |data|
        data.delete('version')
        data['actual_start_time'] = data.delete('start_time')
        data['actual_end_time'] = data.delete('end_time')
      }
    end

    def stderr_merged?
      metadata['stdout_path'] == metadata['stderr_path']
    end

    private

    # NOTE: Requires parity with job_dir
    def task_dir
      @task_dir ||= File.join(FlightJob.config.jobs_dir, job_id, 'tasks')
    end

    # A glob of all possible state index files
    def state_index_files
      Dir.glob(self.class.state_index_path(job_id, index, '*')).sort
    end

    # The correct index file
    def state_index_file
      self.class.state_index_path(job_id, index, metadata['state'])
    end

    def reform_state_index_file
      return if state_index_files == [state_index_file]
      state_index_files.each { |f| FileUtils.rm_f f }
      FileUtils.mkdir_p File.dirname(state_index_file)
      FileUtils.touch state_index_file
    end

    def end_time_index_files
      Dir.glob(self.class.end_time_index_path(job_id, index, '*')).sort
    end

    def end_time_index_file
      time = metadata['end_time']
      return nil unless time
      self.class.end_time_index_path(job_id, index, time)
    end

    def reform_end_time_index_file
      files = end_time_index_files
      file = end_time_index_file
      return if files.empty? && file.nil?
      return if files == [file]
      files.each { |f| FileUtils.rm_f f }
      if file
        FileUtils.mkdir_p File.dirname(file)
        FileUtils.touch file
      end
    end
  end
end

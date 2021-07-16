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
require 'securerandom'
require 'json_schemer'

require_relative '../render_context'

module FlightJob
  class Script < ApplicationModel
    SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required" => ['created_at', 'script_name'],
      "properties" => {
        'created_at' => { 'type' => 'string', 'format' => 'date-time' },
        'template_id' => { 'type' => 'string' },
        'script_name' => { 'type' => 'string' },
        'answers' => { 'type' => 'object' }
      }
    })

    def self.load_all
      Dir.glob(new(id: '*').metadata_path).map do |path|
        id = File.basename(File.dirname(path))
        script = new(id: id)
        if script.valid?(:load)
          script
        else
          FlightJob.logger.error("Failed to load missing/invalid script: #{id}")
          FlightJob.logger.debug(script.errors)
          nil
        end
      end.reject(&:nil?).sort
    end

    attr_reader :id
    attr_writer :notes

    validates :id, presence: true, length: { maximum: FlightJob.config.max_id_length },
              format: { with: /\A[a-zA-Z0-9_-]+\Z/,
                        message: 'can only contain letters, numbers, hyphens, and underscores' }
    validates :id, format: { with: /\A[[:alnum:]].*\Z/, message: 'must start with a letter or a number' }

    validate do
      # Skip this validation on :id_check
      next if validation_context == :id_check

      unless (errors = SCHEMA.validate(metadata).to_a).empty?
        @errors.add(:metadata, 'is not valid')
        path_tag = File.exists?(metadata_path) ? metadata_path : id
        FlightJob.logger.debug("Invalid metadata: #{path_tag}\n") do
          JSON.pretty_generate(errors)
        end
      end
    end

    validate on: :load do
      # Ensures the metadata file exists
      unless File.exists? metadata_path
        @errors.add(:metadata_path, 'does not exist')
        next
      end

      # Migrate legacy scripts to the new file format
      if !File.exists?(workload_path) && File.exists?(legacy_script_path)
        FileUtils.ln_s File.basename(legacy_script_path), workload_path
      end

      # Ensures the workload exists
      unless File.exists? workload_path
        @errors.add(:workload_path, 'does not exist')
      end
    end

    validate on: :id_check do
      # Ensure the ID has not been taken
      # NOTE: This negates the need to check if metadata_path exists
      if Dir.exists? File.expand_path(id, FlightJob.config.scripts_dir)
        @errors.add(:id, :already_exists, message: 'already exists')
      end
    end

    validate on: :render do
      # Ensures the template is valid
      template = load_template
      if template.nil?
        @errors.add(:template, 'could not be resolved')
      elsif ! template.valid?(:verbose)
        @errors.add(:template, 'is not valid')
        FlightJob.logger.debug("Template errors: #{template_id}\n") do
          template.errors.full_messages.join("\n")
        end
      end
    end

    def initialize(**original)
      opts = original.dup
      if id = opts.delete(:id)
        # Set the provided ID
        @id = id
      else
        # Implicitly generate an ID
        @id ||= begin
          candidate = false
          until candidate do
            # Generate a 8 byte base64 string
            # NOTE: 6 bytes of randomness becomes 8 base64-chars
            candidate = SecureRandom.urlsafe_base64(6)

            # Ensure the candidate start with an alphanumeric character
            unless /[[:alnum:]]/ =~ candidate[0]
              candidate = false
              next
            end

            # Check the candidate has not been taken
            # NOTE: This does not reserve the candidate, it needs to be checked
            #       again just before the script is rendered
            if Dir.exists? File.expand_path(candidate, FlightJob.config.scripts_dir)
              candidate = false
              next
            end
          end
          candidate
        end
      end

      super(**opts)
    end

    # NOTE: Only used for a shorthand existence check, full validation is required in
    # before it can be used
    def exists?
      File.exists? metadata_path
    end

    def notes
      @notes ||= if File.exists? notes_path
                   File.read notes_path
                 else
                   ''
                 end
    end

    def metadata_path
      if ! @metadata_path.nil?
        @metadata_path
      else
        @metadata_path ||= File.join(FlightJob.config.scripts_dir, id, 'metadata.yaml')
      end
    end

    # Used to migrate the script to the new format
    # NOTE: This does not need to be cached as it is rarely used
    def legacy_script_path
      File.join(Flight.config.scripts_dir, id, script_name)
    end

    def workload_path
      @workload_path ||= File.join(FlightJob.config.scripts_dir, id, 'workload')
    end

    # NOTE: This is the currently cached version of the script, which
    # will be re-rendered periodically. It is not used in the job submission
    def cached_path
      @cached_path ||= File.join(FlightJob.config.scripts_dir, id, 'cache', script_name)
    end

    # Creates a symlink to the workload path based on the script_name file extension
    # This prompts the editor to use the correct syntax highlighting
    def alternative_workload_path
      ext = File.extname(script_name || '')
      return workload_path if ext.empty?
      (workload_path + ext).tap do |path|
        unless File.exists?(path)
          FileUtils.ln_s('workload', path)
        end
      end
    end

    # XXX: Remove me!
    def script_path
      Flight.logger.warn "DEPRECATED: Script#script_path has been removed in favour of workload_path"
      Flight.logger.warn caller[0]
      workload_path
    end

    def notes_path
      @notes_path ||= File.join(FlightJob.config.scripts_dir, id, 'notes.md')
    end

    def created_at
      metadata['created_at']
    end

    def template_id
      metadata['template_id']
    end

    def template_id=(id)
      metadata['template_id'] = id
    end

    def script_name
      metadata['script_name']
    end

    def script_name=(name)
      metadata['script_name'] = name
    end

    # NOTE: For backwards compatibility, the 'answers' are not strictly required
    # This may change in a few release
    def answers
      metadata['answers'] ||= {}
    end

    def answers=(object)
      metadata['answers'] = object
    end

    def load_template
      return nil unless template_id
      Template.new(id: template_id)
    end

    def render
      [
        renderer.render_directives,
        renderer.render_adapter,
        File.read(workload_path)
      ].join("\n").tap do |content|
        FileUtils.mkdir_p File.dirname(cached_path)
        File.write cached_path, content
      end
    end

    def render_and_save
      # Ensures it claims the ID
      # NOTE: As this is done after validation, it may trigger a race condition
      #       This could cause the command to fail, whilst the other succeeds
      #       Subsequent commands will detect the ID has been taken
      begin
        FileUtils.mkdir_p FlightJob.config.scripts_dir
        FileUtils.mkdir File.expand_path(id, FlightJob.config.scripts_dir)
      rescue Errno::EEXIST
        raise_duplicate_id_error
      end

      # Writes the data to disk
      save_metadata
      save_notes
      File.write(workload_path, renderer.render_workload)

      # Update the various file permissions
      FileUtils.chmod(0600, workload_path)
      FileUtils.chmod(0600, metadata_path)

      # Render the script
      render
    end

    def save_metadata
      File.write metadata_path, YAML.dump(metadata)
      FileUtils.chmod(0600, metadata_path)
    end

    def save_notes
      File.write notes_path, notes
      FileUtils.chmod(0600, notes_path)
    end

    def serializable_hash(opts = nil)
      opts ||= {}
      answers # Ensure the answers have been set
      {
        "id" => id,
        "notes" => notes,
        "path" => cached_path,
        "workload_path" => workload_path
      }.merge(metadata).tap do |hash|
        if opts.fetch(:include, []).include? 'template'
          hash['template'] = load_template
        end
        if opts.fetch(:include, []).include? 'jobs'
          # NOTE: Consider using a file registry instead
          hash['jobs'] = Job.load_all.select { |s| s.script_id == id }
        end
      end
    end

    def raise_duplicate_id_error
      raise DuplicateError, "The ID already exists!"
    end

    def renderer
      return @renderer if @renderer

      # Ensure the script is in a valid state
      unless valid?(:render)
        FlightJob.logger.error("The script is invalid:\n") do
          errors.full_messages.join("\n")
        end
        raise InternalError, 'Unexpectedly failed to render the script!'
      end

      @renderer ||= FlightJob::RenderContext.new(
        template: load_template, answers: answers
      )
    end

    protected

    def <=>(other)
      if id.nil? || id.nil?
        0 # This case SHOULD NOT be reached in practice, so further sorting isn't required
      else
        id <=> other.id
      end
    end

    private

    # NOTE: The raw metadata is exposed through the CLI with the --json flag.
    # This allows it to be directly passed to the API layer.
    # Consider refactoring when introducing a non-backwards compatible change
    def metadata
      @metadata ||= if File.exists?(metadata_path)
                      YAML.load File.read(metadata_path)
                    else
                      { 'created_at' => DateTime.now.rfc3339 }
                    end
    end
  end
end

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

module FlightJob
  class Script < ApplicationModel
    SCHEMA = JSONSchemer.schema({
      "$comment" => "strip-schema",
      "type" => "object",
      "additionalProperties" => false,
      "required" => ['created_at', 'script_name'],
      "properties" => {
        # ----------------------------------------------------------------------------
        # Required
        # ----------------------------------------------------------------------------
        'created_at' => { 'type' => 'string', 'format' => 'date-time' },
        'script_name' => { 'type' => 'string' },
        # ----------------------------------------------------------------------------
        # Psuedo - Required
        #
        # These should *probably* become required on the next major release of the metadata
        # ----------------------------------------------------------------------------
        'answers' => { 'type' => 'object' },
        'tags' => { 'type' => 'array', 'items' => { 'type' => 'string' }},
        'template_id' => { 'type' => 'string' },
        'version' => { 'const' => 0 },
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
          FlightJob.logger.info(script.errors.full_messages.join("\n"))
          nil
        end
      end.reject(&:nil?).sort
    end

    delegate :generate_submit_args, to: :load_template

    attr_accessor :id
    attr_writer :notes

    validates :id, presence: true, length: { maximum: FlightJob.config.max_id_length },
              format: { with: /\A[a-zA-Z0-9_-]+\Z/,
                        message: 'can only contain letters, numbers, hyphens, and underscores' },
              unless: -> { validation_context == :render }
    validates :id, format: { with: /\A[[:alnum:]].*\Z/, message: 'must start with a letter or a number' },
              unless: -> { validation_context == :render }

    validate do
      # Skip this validation on :id_check
      next if validation_context == :id_check

      unless (schema_errors = SCHEMA.validate(metadata).to_a).empty?
        path_tag = File.exist?(metadata_path) ? metadata_path : id
        FlightJob.logger.info("Invalid metadata: #{path_tag}\n")
        JSONSchemaErrorLogger.new(schema_errors, :info).log
        errors.add(:metadata, 'is not valid')
      end
    end

    validate on: :load do
      # Ensures the metadata file exists
      unless File.exist? metadata_path
        errors.add(:metadata_path, 'does not exist')
        next
      end

      # Ensures the script file exists
      unless File.exist? script_path
        legacy_path = File.join(Flight.config.scripts_dir, id, script_name)
        if File.exist?(legacy_path)
          # Migrate legacy scripts to the script_path
          FileUtils.ln_s script_name, script_path
        else
          # Error as it is missing
          @errors.add(:script_path, 'does not exist')
        end
      end
    end

    validate on: :id_check do
      # Ensure the ID has not been taken
      # NOTE: This negates the need to check if metadata_path exists
      if Dir.exists? File.expand_path(id, FlightJob.config.scripts_dir)
        errors.add(:id, :already_exists, message: 'already exists')
      end
    end

    validate on: :render do
      # Ensures the template is valid
      template = load_template
      if template.nil?
        errors.add(:template, 'could not be resolved')
      elsif !template.valid?
        errors.add(:template, 'is not valid')
        FlightJob.logger.info("Template errors: #{template_id}\n") do
          template.errors.full_messages.join("\n")
        end
      end
    end

    # NOTE: Only used for a shorthand existence check, full validation is required in
    # before it can be used
    def exists?
      File.exist? metadata_path
    end

    def notes
      @notes ||= if File.exist? notes_path
                   File.read notes_path
                 else
                   ''
                 end
    end

    def metadata_path
      # Sometimes we render a script that has no ID; in this case, it doesn't
      # exist outside of the execution scope, and will not have a path.
      return nil if id.nil?
      @metadata_path ||= File.join(FlightJob.config.scripts_dir, id, 'metadata.yaml')
    end

    def script_path
      @script_path ||= File.join(FlightJob.config.scripts_dir, id, 'script.sh')
    end

    def notes_path
      @notes_path ||= File.join(FlightJob.config.scripts_dir, id, 'notes.md')
    end

    def created_at
      metadata['created_at']
    end

    def tags
      metadata['tags'] || []
    end

    def tags=(tags)
      metadata_setter('tags', tags)
    end

    def template_id
      metadata['template_id']
    end

    def template_id=(id)
      metadata_setter('template_id', id)
    end

    def script_name
      metadata['script_name']
    end

    def script_name=(name)
      metadata_setter('script_name', name)
    end

    # NOTE: For backwards compatibility, the 'answers' are not strictly required
    # This may change in a few release
    def answers
      metadata['answers']
    end

    def answers=(object)
      metadata_setter('answers', object)
    end

    def load_template
      return nil unless template_id
      Template.new(id: template_id)
    end

    def render_and_save
      # Ensure the renderer is defined
      renderer

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
      File.write(script_path, renderer.render)

      # Makes the script executable and metadata read/write
      FileUtils.chmod(0700, script_path)
      FileUtils.chmod(0600, metadata_path)
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
        "path" => script_path,
        "tags" => tags,
      }.merge(metadata).tap do |hash|
        if Flight.config.includes.include? 'template'
          hash['template'] = load_template
        end
        if Flight.config.includes.include? 'jobs'
          hash['jobs'] = Job.load_all
            .select { |j| j.script_id == id && j.valid? }
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

      @renderer ||= FlightJob::Renderers::ScriptRenderer.new(
        template: load_template, answers: answers
      )
    end

    protected

    def <=>(other)
      FancyIdOrdering.call(self.id, other.id)
    end

    private

    # Allows keys to be set within the metadata without loading the file
    # This allows the 'id' to remain unset during the 'initialize' method
    def metadata_setter(key, value)
      if @metadata
        @metadata[key] = value
      else
        @provisional_metadata ||= {}
        @provisional_metadata[key] = value
      end
    end

    # NOTE: The raw metadata is exposed through the CLI with the --json flag.
    # This allows it to be directly passed to the API layer.
    # Consider refactoring when introducing a non-backwards compatible change
    def metadata
      @metadata ||= if metadata_path && File.exist?(metadata_path)
        YAML.load File.read(metadata_path)
      else
        { 'version' => 0, 'created_at' => DateTime.now.rfc3339 }
      end.tap do |hash|
        if hash.is_a? Hash
          if @provisional_metadata
            hash.merge!(@provisional_metadata)
            @provisional_metadata = nil
          end
          hash['answers'] ||= {}
        end
      end
    end
  end
end

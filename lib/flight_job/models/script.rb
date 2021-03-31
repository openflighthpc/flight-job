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
require 'pastel'

require_relative '../render_context'

module FlightJob
  class Script < ApplicationModel
    ID_REGEX = /\A[\w.-]+\Z/

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
      Dir.glob(metadata_path('*')).map do |path|
        id = File.basename(File.dirname(path))
        script = new(id: id)
        if script.valid?(:load)
          script
        else
          FlightJob.logger.error("Failed to load missing/invalid script: #{id}")
          FlightJob.logger.debug(script.errors.full_messages.join("\n"))
          nil
        end
      end.reject(&:nil?)
    end

    def self.metadata_path(id)
      File.join(FlightJob.config.scripts_dir, id, 'metadata.yaml')
    end

    def self.public_id_path(public_id, internal_id)
      File.join(FlightJob.config.scripts_dir, internal_id, "public-#{public_id}")
    end

    def self.reserve_public_id(id, write: true)
      # Check if the id is already taken
      return false if lookup_internal_id(id)

      # Attempt to obtain the reservation
      path = public_id_path(id, 'reservations')
      if write
        FileUtils.mkdir_p File.dirname(path)
        File.open(path, 'a') { |f| f.puts(Process.pid) }
      end

      # Ensure the process obtained the reservation
      return false unless File.exists?(path)
      File.read(path).split("\n").each do |pid|
        pid = pid.to_i
        break if Process.pid == pid
        begin
          # Check if the priority process is still running
          # This allows the 'id' reservation to be released if not used
          Process.kill(0, pid)
          return false
        rescue Errno::EPERM
          # Priority process does exist, but is (probably) owned by another user
          return false
        rescue Errno::ESRCH
          # NOOP: The priority process no longer exists, keep checking
        end
      end

      # Ensure the ID still isn't taken (prevents race conditions
      return false if lookup_internal_id(id)
      true
    end


    # TODO: Shortcut this method by globbing for the public_id directly
    def self.lookup_internal_id(public_id)
      paths = Dir.glob(public_id_path(public_id, '*'))
      paths.delete(public_id_path(public_id, 'reservations'))
      if paths.length > 1
        raise InternalError, <<~ERROR
          Located multiple scripts with the same public_id:
          #{paths.join("\n")}
        ERROR
      end
      return nil if paths.empty?
      File.basename(File.dirname(paths.first))
    end

    def self.lookup_public_id(internal_id)
      # Attempt to glob directly for the public_id
      paths = Dir.glob(public_id_path('*', internal_id)).sort

      # Ensure there are no duplicates (this should not happen in practice)
      if paths.length > 1
        msg = <<~ERROR.chomp
          Detected duplicate public_ids for job '#{internal_id}':
          #{paths.join("\n")}

          This may result in unusual/undefined behaviour of various commands!
          Please remove all but one of the files to suppress this message.
        ERROR
        FlightJob.logger.error msg
        $stderr.puts Pastel.new.red msg
      end

      # Return the id
      if paths.length > 0
        File.basename(paths.first).split('-', 2).last
      # Default to internal_id for legacy scripts (circa v2.0.0)
      # NOTE: Consider removing
      elsif File.exists? metadata_path(internal_id)
        path = public_id_path(internal_id, internal_id)
        FileUtils.mkdir_p File.dirname(path)
        FileUtils.touch path
        internal_id
      end
    end

    attr_writer :notes, :public_id

    # NOTE: The length is not validated as the maximum is subject to be changed
    validates :internal_id, presence: true
    validates :public_id, presence: true, format: { with: ID_REGEX }

    validate do
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

      # Ensures the script file exists
      unless File.exists? script_path
        @errors.add(:script_path, 'does not exist')
      end
    end

    validate on: :render do
      # Ensures the metadata does not exists
      if File.exists? metadata_path
        @errors.add(:metadata_path, 'already exists')
        next
      end

      # Ensure the reservation has been obtained
      unless self.class.reserve_public_id(public_id, write: false)
        @errors.add(:public_id, 'has not be reserved')
      end

      # Ensures the script does not exists
      if File.exists? script_path
        @errors.add(:script_path, 'already exists')
      end

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

    attr_reader :internal_id

    def initialize(**input_opts)
      opts = input_opts.dup
      @internal_id = opts.delete(:internal_id) || opts.delete(:id) || SecureRandom.uuid
      super(opts)
    end

    def id
      internal_id
    end

    def public_id
      @public_id ||= self.class.lookup_public_id(internal_id)
    end

    # NOTE: Only used for a shorthand existence check, full validation is required
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
      # NOTE: Do not cache, as the 'id' may change whilst being implicitly
      # determined
      self.class.metadata_path(internal_id)
    end

    def script_path
      if ! @script_path.nil?
        @script_path
      elsif id && script_name
        @script_path = File.join(FlightJob.config.scripts_dir, id, script_name)
      else
        @errors.add(:script_path, 'cannot be determined')
        @script_path = false
      end
    end

    def notes_path
      @notes_path ||= File.join(FlightJob.config.scripts_dir, id, 'notes.md')
    end

    def public_id_path
      # NOTE: This path should not be cached
      self.class.public_id_path(public_id, internal_id)
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
      @script_path = nil
      metadata['script_name'] = name
    end

    # NOTE: For backwards compatibility, the 'answers' are not strictly required
    # This may change in a few release
    def answers
      metadata['answers']
    end

    def answers=(object)
      metadata['answers'] = object
    end

    def load_template
      return nil unless template_id
      Template.new(id: template_id)
    end

    # NOTE: This method is used to generate a rendered template without saving
    def render
      # Ensure the script is in a valid state
      unless valid?(:render)
        FlightJob.logger.error("The script is invalid:\n") do
          errors.full_messages.join("\n")
        end
        raise InternalError, 'Unexpectedly failed to render the script!'
      end

      # Render the content
      FlightJob::RenderContext.new(
        template: load_template, answers: answers
      ).render
    end

    def render_and_save
      content = render

      # Write the public_id
      FileUtils.mkdir_p File.dirname(public_id_path)
      FileUtils.touch public_id_path

      # Writes the data to disk
      save_metadata
      save_notes

      # Write the script
      File.write(script_path, content)
      FileUtils.chmod(0700, script_path)

      # NOTE: The metadata must be wrote last to denote the script now
      # exists (excluding cleanup the reservation)
      File.write(metadata_path, YAML.dump(metadata))
    end

    def save_metadata
      FileUtils.mkdir_p File.dirname(metadata_path)
      File.write metadata_path, YAML.dump(metadata)
      FileUtils.chmod(0600, metadata_path)
    end

    def save_notes
      FileUtils.mkdir_p File.dirname(notes_path)
      File.write notes_path, notes
      FileUtils.chmod(0600, notes_path)
    end

    def serializable_hash
      metadata.merge({
        # NOTE: Override the 'id' field to be public!
        # This allows it to be implicitly used with the CLI without any flag modifications
        "id" => public_id,
        'internal_id' => internal_id,
        'public_id' => public_id,
        "notes" => notes,
        "path" => script_path
      })
    end

    private

    # NOTE: The raw metadata is exposed through the CLI with the --json flag.
    # This allows it to be directly passed to the API layer.
    # Consider refactoring when introducing a non-backwards compatible change
    def metadata
      @metadata ||= if File.exists?(metadata_path)
                      YAML.load(File.read(metadata_path)).tap do |data|
                        data['answers'] ||= {}
                      end
                    else
                      { 'created_at' => DateTime.now.rfc3339, 'answers' => {} }
                    end
    end
  end
end

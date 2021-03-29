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
          FlightJob.logger.debug(script.errors)
          nil
        end
      end.reject(&:nil?)
    end

    def self.metadata_path(id)
      File.join(FlightJob.config.scripts_dir, id, 'metadata.yaml')
    end

    def self.internal_id_path(public_id, internal_id)
      File.join(FlightJob.config.scripts_dir, public_id, "internal-#{internal_id}")
    end

    attr_writer :id, :notes

    validates :id, presence: true

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
      unless reserved?
        @errors.add(:id, 'could not be reserved')
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

    # TODO: Rename the id method to public_id
    attr_reader :id
    def public_id
      id
    end

    def initialize(**opts)
      # Attempt to set the ID up front from the provided options
      unless @id = opts.delete(:id)
        # Apply the user's reserved id
        # NOTE: It is not checked here to allow the caller to preform the error handling
        if id = opts.delete(:reserve_id)
          self.reserve_id = id

        # Attempt to implicitly generate an ID from the provided script_name
        elsif name = opts[:script_name]
          current = Dir.glob(self.class.metadata_path("#{name}.*")).map do |path|
            id = File.basename File.dirname(path)
            index = id.split('.').last
            /\A\d+\Z/.match?(index) ? index.to_i : nil
          end.reject(&:nil?).max

          # Attempt to reserve the archetype script if no indices have been used
          if current.nil?
            self.reserve_id = name
            current = 0
          end

          # Increment the indices until a reservation can be made
          until reserved?
            current = current + 1
            self.reserve_id = "#{name}.#{current}"
          end
        else
          # Error as an ID could not be determined
          raise InternalError, <<~ERROR
            Either an id: or script_name: must be provided on initalization
          ERROR
        end
      end

      # Initialize the remaining fields
      # NOTE: This allows them to be saved in any existing metadata hash which
      # is dependant on the ID being set
      super(opts)
    end

    # NOTE: This is the ID used to refer to the scripts from existing jobs. It
    # is static to the lifetime of the script even after being renamed!
    #
    # PS: It will be inferred from the existing public_id for legacy scripts
    def internal_id
      @internal_id ||= begin
        # Determine the internal_id from the path file
        paths = Dir.glob(self.class.internal_id_path(public_id, '*')).sort

        # Ensure there are no duplicates (this should not happen in practice)
        if paths.length > 1
          msg = <<~ERROR.chomp
            Detected duplicate internal_ids for job '#{id}':
            #{paths.join("\n")}

            This may result in unusual/undefined behaviour of various commands!
            Please remove all but one of the files to suppress this message.
          ERROR
          FlightJob.logger.error msg
          $stderr.puts Pastel.new.red msg
        end

        # Determine the ID, generate a new one, or use the legacy public_id
        if paths.empty? && exists?
          # NOTE: This is for legacy scripts only (circa v2.0.0), consider removing
          FileUtils.touch self.class.internal_id_path(public_id, public_id)
          public_id
        elsif paths.empty?
          SecureRandom.uuid
        else
          File.basename(paths.first).split('-').last
        end
      end
    end

    # Attempt to obtain the reservation for an ID
    # NOTE: The reservation is not checked at this point as the error handling
    # needs to be context specific. It does however get checked in the validation
    def reserve_id=(candidate)
      @id = candidate
      FileUtils.mkdir_p File.dirname(reservation_path)
      # Append the PID to the file
      File.open(reservation_path, 'a') { |f| f.puts(Process.pid) }
      @id
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

    # Checks if the process has successfully reserved the ID
    def reserved?
      return false unless @id
      return false unless File.exists?(reservation_path)
      File.read(reservation_path).split("\n").each do |pid|
        pid = pid.to_i
        return true if Process.pid == pid
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
      return false
    end

    def metadata_path
      @metadata_path ||= self.class.metadata_path(id)
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

    # Used to reserve an ID before the script can be created. Only the process who's PID
    # appears at the top of this list owns the ID. The reservation file becomes redundant
    # once the `metadata` file exists.
    def reservation_path
      # NOTE: This path should not be cached
      File.join(FlightJob.config.scripts_dir, id, 'reservation.pids')
    end

    def internal_id_path
      @internal_id_path ||= self.class.internal_id_path(public_id, internal_id)
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
      metadata['answers'] ||= {}
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

      # Write the internal Id
      FileUtils.mkdir_p File.dirname(internal_id_path)
      FileUtils.touch internal_id_path

      # Writes the data to disk
      save_metadata
      save_notes

      # Write the script
      File.write(script_path, content)
      FileUtils.chmod(0700, script_path)

      # Remove the reservation
      FileUtils.rm_f reservation_path
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
      answers # Ensure the answers have been set
      {
        "id" => internal_id,
        'internal_id' => internal_id,
        'public_id' => public_id,
        "notes" => notes,
        "path" => script_path
      }.merge(metadata)
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

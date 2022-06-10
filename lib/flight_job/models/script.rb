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
require 'securerandom'
require_relative 'script/metadata'
require_relative 'script/migrate_script'
require_relative '../matcher'

module FlightJob
  class Script < ApplicationModel

    def self.load_all(opts = nil)
      glob = File.join(Flight.config.scripts_dir, "*", "metadata.yaml")
      Dir.glob(glob).map do |path|
        id = File.basename(File.dirname(path))
        script = new(id: id)
        if script.pass_filter?(opts)
          if script.valid?(:load)
            script
          else
            FlightJob.logger.error("Failed to load missing/invalid script: #{id}")
            FlightJob.logger.info(script.errors.full_messages.join("\n"))
            nil
          end
        end
      end.compact.sort
    end

    after_initialize MigrateScript, if: :persisted?

    delegate :generate_submit_args, to: :load_template
    delegate(*Metadata.attribute_names, to: :metadata)
    delegate :tags=, :template_id=, :script_name=, :answers=, to: :metadata
    delegate :persisted?, to: :metadata

    attr_accessor :id

    validates :id, presence: true, length: { maximum: FlightJob.config.max_id_length },
              format: { with: /\A[a-zA-Z0-9_-]+\Z/,
                        message: 'can only contain letters, numbers, hyphens, and underscores' },
              unless: -> { validation_context == :render }
    validates :id, format: { with: /\A[[:alnum:]].*\Z/, message: 'must start with a letter or a number' },
              unless: -> { validation_context == :render }

    validate on: :load do
      unless File.exist? metadata_path
        errors.add(:metadata_path, 'does not exist')
        next
      end
      unless File.exist? script_path
        errors.add(:script_path, 'does not exist')
        next
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

    def pass_filter?(filters)
      @_matcher ||= Matcher.new(filters, {id: id, template: template_id})
      @_matcher.matches?
    end

    # NOTE: Only used for a shorthand existence check, full validation is required in
    # before it can be used
    def exists?
      File.exist? metadata_path
    end

    def notes
      @notes ||= Notes.new(id).tap { |n| n.read }
    end

    def initialize_notes(notes = "")
      @notes ||= Notes.new(id).tap { |n| n.write(notes) }
    end

    def script_path
      @script_path ||= File.join(FlightJob.config.scripts_dir, id, 'script.sh')
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
      metadata.save
      notes.save
      File.write(script_path, renderer.render)

      # Makes the script executable and metadata read/write
      FileUtils.chmod(0700, script_path)
      FileUtils.chmod(0600, metadata_path)
    end

    def serializable_hash(opts = nil)
      opts ||= {}
      answers # Ensure the answers have been set
      {
        "id" => id,
        "notes" => notes.read,
        "path" => script_path,
        "tags" => tags,
      }.merge(metadata).tap do |hash|
        if Flight.config.includes.include? 'template'
          hash['template'] = load_template
        end
        if Flight.config.includes.include? 'jobs'
          hash['jobs'] = Job.load_all
                            .select { |j| j.script_id == id && j.valid? }
                            .map { |j| j.decorate }
        end
      end
    end

    def raise_duplicate_id_error
      raise DuplicateError, "The ID already exists!"
    end

    def renderer
      return @renderer if defined?(@renderer) && @renderer

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

    def initialize_metadata(template, answers)
      if persisted?
        Metadata.load_from_path(metadata_path, self)
      else
        @metadata = Metadata.from_template(template, answers, self)
      end
    end

    def metadata
      @metadata ||= if File.exist?(metadata_path)
                      Metadata.load_from_path(metadata_path, self)
                    else
                      Flight.logger.warn("Setting metadata to empty hash for script #{id}; this probably isn't right")
                      Metadata.blank(metadata_path, self)
                    end
    end

    def metadata_path
      # Sometimes we render a script that has no ID; in this case, it doesn't
      # exist outside of the execution scope, and will not have a path.
      return nil if id.nil?
      @metadata_path ||= File.join(FlightJob.config.scripts_dir, id, 'metadata.yaml')
    end


    protected

    def <=>(other)
      FancyIdOrdering.call(self.id, other.id)
    end

  end
end

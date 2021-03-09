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
        'script_name' => { 'type' => 'string' }
      }
    })

    def self.load_all
      Dir.glob(new(id: '*').metadata_path).map do |path|
        self.load(File.basename(File.dirname(path)))
      end.reject(&:nil?)
    end

    def self.load(id)
      script = new(id: id)
      if script.valid?(:load)
        script
      else
        FlightJob.logger.error("Failed to load missing/invalid script: #{id}")
        FlightJob.logger.debug(script.errors)
        nil
      end
    end

    attr_writer :id

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

    def id
      @id ||= SecureRandom.uuid
    end

    def metadata_path
      if ! @metadata_path.nil?
        @metadata_path
      else
        @metadata_path ||= File.join(FlightJob.config.scripts_dir, id, 'metadata.yaml')
      end
    end

    def script_path
      if ! @script_path.nil?
        @script_path
      elsif id && script_name
        @script_path = File.join(FlightJob.config.scripts_dir, id, script_name)
      else
        @errors.add(:script_path, 'can not be determined')
      end
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

    def load_template
      return nil unless template_id
      Template.new(id: template_id)
    end

    # XXX: Eventually the answers will likely be saved with the script
    def render(**answers)
      # Ensure the script is in a valid state
      unless valid?(:render)
        FlightJob.logger.error("The script is invalid:\n") do
          errors.full_messages.join("\n")
        end
        raise InternalError, 'Unexpectedly failed to render the script!'
      end

      # Render the content
      content = FlightJob::RenderContext.new(
        template: load_template, answers: answers
      ).render

      # Writes the data to disk
      FileUtils.mkdir_p File.dirname(metadata_path)
      File.write(metadata_path, YAML.dump(metadata))
      File.write(script_path, content)

      # Makes the script executable and metadata read/write
      FileUtils.chmod(0700, script_path)
      FileUtils.chmod(0600, metadata_path)
    end

    private

    def metadata
      @metadata ||= if File.exists?(metadata_path)
                      YAML.load File.read(metadata_path)
                    else
                      { 'created_at' => DateTime.now.rfc3339 }
                    end
    end
  end
end

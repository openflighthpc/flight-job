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

require 'json_schemer'
require 'simple_jsonapi_client'
require 'active_support/inflector'

require 'tsort'

module FlightJob
  class BaseRecord < SimpleJSONAPIClient::Base
    def self.inherited(base)
      base.const_set(
        'TYPE',
        base.name.split('::').last.sub(/Record\Z/, '').underscore.dasherize
      )
      base.const_set('COLLECTION_URL', File.join(Config::CACHE.base_url_path, Config::CACHE.api_prefix, base::TYPE))
      base.const_set('INDIVIDUAL_URL', "#{base::COLLECTION_URL}/%{id}")
      base.const_set('SINGULAR_TYPE', base::TYPE.singularize)
    end

    ##
    # Override the delete method to nicely handle missing records
    def delete
      super
    rescue SimpleJSONAPIClient::Errors::NotFoundError
      if $!.response['content-type'] == 'application/vnd.api+json'
        # Handle proper API errors
        raise MissingError, <<~ERROR.chomp
          Could not locate #{self.class::SINGULAR_TYPE}: "#{self.id}"
        ERROR
      else
        # Fallback to the top level error handler
        raise e
      end
    end
  end

  class TemplatesRecord < BaseRecord
    attributes :name, :synopsis, :description
  end

  class ScriptsRecord < BaseRecord
    attributes :name

    has_one :template, class_name: 'FlightJob::TemplatesRecord'
  end

  class QuestionsRecord < BaseRecord
    ASK_WHEN_SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "additionalProperties" => false,
      "required": ["value", "eq"],
      "properties" => {
        "value" => {
          "type" => "string", "pattern" => "^question\.[a-zA-Z_-]+\.answer$"
        },
        "eq" => { "type" => ["string"] }
      }
    })

    FORMAT_SCHEMA = JSONSchemer.schema({
      "type" => "object",
      "required" => ["type"],
      "properties" => {
        # NOTE: This is the field named "type" not a specification
        "type" => { "type" => "string", "enum" => ["select", "text", "multiline_text"] }
      },
      "if" => { "properties" => { "type" => { "const" => "select" } } },
      "then" => {
        "required" => ["type", "options"],
        "properties" => {
          "options" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "additionalProperties" => false,
              "required" => ["text", "value"],
              "properties" => {
                "text" => { "type" => "string" },
                "value" => { "type" => "string" }
              }
            }
          }
        }
      }
    })

    attributes :text, :default, :format, :askWhen

    def related_question_id
      return nil unless askWhen
      askWhen['value'].split('.')[1]
    end

    def supported?
      if askWhen && !(ask_errors = ASK_WHEN_SCHEMA.validate(askWhen).to_a).empty?
        Config::CACHE.logger.error("Unsupported askWhen for question: #{id}")
        Config::CACHE.logger.debug(JSON.pretty_generate(ask_errors))
        return false
      end
      unless (format_errors = FORMAT_SCHEMA.validate(format).to_a).empty?
        Config::CACHE.logger.error("Unsupported format for question: #{id}")
        Config::CACHE.logger.debug(JSON.pretty_generate(format_errors))
        return false
      end
      true
    end
  end
end

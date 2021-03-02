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

require 'simple_jsonapi_client'
require 'active_support/inflector'

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
end

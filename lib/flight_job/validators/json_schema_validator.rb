#==============================================================================
# Copyright (C) 2022-present Alces Flight Ltd.
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
  # Active model validator wrapping a JSONSchemer validator.
  class JsonSchemaValidator < ActiveModel::Validator
    def initialize(options)
      @schema = options[:schema]
      @json_method = options[:json_method]
      @error_key = options[:error_key]
    end

    def validate(record)
      json = record.send(@json_method)
      schema_errors = @schema.validate(json).to_a
      return if schema_errors.empty?

      record.errors.add(@error_key, 'is not valid')
      JSONSchemaErrorLogger.new(schema_errors, :warn).log
    end
  end
end

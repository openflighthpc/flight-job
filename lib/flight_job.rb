# frozen_string_literal: true
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

require 'active_support/core_ext/module/delegation'

require_relative 'flight_job/configuration'
require_relative 'flight_job/command'
require_relative 'flight_job_migration'

module FlightJob
  class << self
    delegate :config, :env, :logger, :root, to: Flight
  end

  def self.constantize(sym)
    sym.to_s.dup.split(/[-_]/).each { |c| c[0] = c[0].upcase }.join
  end

  autoload 'FancyIdOrdering', File.expand_path('flight_job/fancy_id_ordering', __dir__)
  autoload 'JSONSchemaErrorLogger', File.expand_path('flight_job/json_schema_error_logger.rb', __dir__)
  autoload 'NameGenerator', File.expand_path('flight_job/name_generator', __dir__)
  autoload 'OneOfParser', File.expand_path('flight_job/one_of_parser.rb', __dir__)
  autoload :QuestionGenerators, File.expand_path('flight_job/question_generators.rb', __dir__)
  autoload 'WrapIndentHelper', File.expand_path('flight_job/wrap_indent_helper.rb', __dir__)

  module Commands
    Dir.glob(File.expand_path('flight_job/commands/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end
  end

  module Decorators
    Dir.glob(File.expand_path('flight_job/decorators/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end
  end

  module JobTransitions
    Dir.glob(File.expand_path('flight_job/job_transitions/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end
  end

  Dir.glob(File.expand_path('flight_job/models/*.rb', __dir__)).each do |path|
    autoload FlightJob.constantize(File.basename(path, '.*')), path
  end

  module Outputs
    Dir.glob(File.expand_path('flight_job/outputs/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end
  end

  module Prompters
    Dir.glob(File.expand_path('flight_job/prompters/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end
  end

  module Renderers
    Dir.glob(File.expand_path('flight_job/renderers/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end
  end
end

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
  autoload 'NameGenerator', File.expand_path('flight_job/name_generator', __dir__)
  autoload 'QuestionPrompter', File.expand_path('flight_job/question_prompter.rb', __dir__)

  # Setup the autoloads for the commands
  module Commands
    Dir.glob(File.expand_path('flight_job/commands/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end
  end

  # Setup the autoloads for the decorators
  module Decorators
    Dir.glob(File.expand_path('flight_job/decorators/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end
  end

  # Setup the autoloads for the job transitions
  module JobTransitions
    Dir.glob(File.expand_path('flight_job/job_transitions/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end
  end

  # Setup the autoloads for models
  Dir.glob(File.expand_path('flight_job/models/*.rb', __dir__)).each do |path|
    autoload FlightJob.constantize(File.basename(path, '.*')), path
  end

  # Setup the autoloads for outputs
  module Outputs
    # NOTE: This method is a bit out of place, but there currently isn't
    # a better location for it
    def self.format_time(rfc3339_time, verbose)
      if rfc3339_time.nil?
        nil
      elsif verbose
        rfc3339_time
      else
        DateTime.rfc3339(rfc3339_time).strftime('%d/%m/%y %H:%M')
      end
    end

    Dir.glob(File.expand_path('flight_job/outputs/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end
  end
end


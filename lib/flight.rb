#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
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
require 'logger'

require 'pastel'

require 'active_support/string_inquirer'
require 'active_support/core_ext/object/blank'

require_relative 'flight_job/errors'

module Flight
  class << self
    def config
      return @config if defined?(@config)
      @config = FlightJob::Configuration.build
      @config.tap do |c|
        logger.info("Flight.env set to #{env.inspect}")
        logger.info("Flight.root set to #{root.inspect}")
        c.__logs__.log_with(logger)
        raise FlightJob::ConfigError, c.rich_error_message unless c.valid?
      end
    end
    alias_method :load_configuration, :config

    def env
      @env ||= ActiveSupport::StringInquirer.new(
        ENV["flight_ENVIRONMENT"].presence || "standalone"
      )
    end

    def root
      @root ||=
        if env.integrated? && ENV["flight_ROOT"].present?
          File.expand_path(ENV["flight_ROOT"])
        elsif env.integrated? && !ENV["flight_ROOT"].present?
          raise GeneralError, "flight_ROOT not set for integrated environment"
        else
          File.expand_path('..', __dir__)
        end
    end

    def logger
      @logger ||= Logger.new(config.log_path).tap do |log|
        next if config.log_level == 'disabled'

        # Determine the level
        level = case config.log_level
        when 'fatal'
          Logger::FATAL
        when 'error'
          Logger::ERROR
        when 'warn'
          Logger::WARN
        when 'info'
          Logger::INFO
        when 'debug'
          Logger::DEBUG
        end

        if level.nil?
          # Log bad log levels
          log.level = Logger::ERROR
          log.error "Unrecognized log level: #{config.log_level}"
        else
          # Sets good log levels
          log.level = level
        end
      end
    end

    def pastel
      @pastel ||= Pastel.new
    end
  end
end

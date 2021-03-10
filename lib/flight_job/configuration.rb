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

# NOTE: Remove this line once deep_transform_keys is removed from flight_configuration
require 'active_support/core_ext/hash/keys'
require 'logger'

require 'flight_configuration'
require_relative 'errors'

module FlightJob
  class Configuration
    extend FlightConfiguration::DSL

    root_path File.expand_path('../..', __dir__)

    config_files File.expand_path('etc/flight-job.yaml', root_path),
                 File.expand_path('etc/flight-job.development.yaml', root_path),
                 File.expand_path('etc/flight-job.local.yaml', root_path),
                 File.expand_path('~/.config/flight/flight-job.yaml')

    # Disable environment variable overrides. This is to allow the API service
    # to wrap the CLI without setting up the environment.
    def self.attribute(*a, **opts)
      opts[:env_var] = false
      super(*a, **opts)
    end

    attribute :templates_dir, default: 'usr/share',
              transform: relative_to(root_path)
    attribute :scripts_dir, default: '~/.local/share/flight/job/scripts',
              transform: relative_to(root_path)
    attribute :jobs_dir, default: '~/.local/share/flight/job/jobs',
              transform: relative_to(root_path)
    attribute :minimum_terminal_width, default: 80
    attribute :log_path, required: false,
              default: '~/.cache/flight/log/share/job.log',
              transform: ->(path) do
                if path
                  relative_to(root_path).tap do |full_path|
                    FileUtils.mkdir_p File.dirname(full_path)
                  end
                else
                  $stderr
                end
              end
    attribute :log_level, default: 'error'
    attribute :development, default: false, required: false
  end

  def self.config
    @config ||= Configuration.load
  end

  def self.logger
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
        log.error "Unrecognized log level: #{log_level}"
      else
        # Sets good log levels
        log.level = level
      end
    end
  end
end

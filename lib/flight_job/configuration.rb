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

require 'active_support/string_inquirer'
require 'active_support/core_ext/object/blank'
require 'i18n/backend'

require 'active_model'

require 'flight_configuration'
require_relative 'errors'

module Flight
  def self.env
    @env ||= ActiveSupport::StringInquirer.new(
      ENV["flight_ENVIRONMENT"].presence || "production"
    )
  end

  def self.root
    @root ||= if env.production? && ENV["flight_ROOT"].present?
      File.expand_path(ENV["flight_ROOT"])
    else
      File.expand_path('../..', __dir__)
    end
  end

  # NOTE: Defined on the top level FlightJob module
  def self.config
    @config ||= FlightJob::Configuration.load
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

module FlightJob
  class Configuration
    extend FlightConfiguration::DSL

    include ActiveModel::Validations

    application_name 'flight-job'

    attribute :templates_dir, default: 'usr/share',
              transform: relative_to(root_path)
    attribute :scripts_dir, default: '~/.local/share/flight/job/scripts',
              transform: relative_to(root_path)
    attribute :jobs_dir, default: '~/.local/share/flight/job/jobs',
              transform: relative_to(root_path)
    attribute :state_map_path, default: 'etc/state-maps/slurm.yaml',
              transform: relative_to(root_path)
    attribute :submit_script_path, default: 'libexec/slurm/submit.sh',
              transform: relative_to(root_path)
    attribute :monitor_script_path, default: 'libexec/slurm/monitor.sh',
              transform: relative_to(root_path)
    attribute :submission_period, default: 3600
    attribute :minimum_terminal_width, default: 80
    validates :_minimum_terminal_width, numericality: { only_integers: true }
    attribute :check_cron, default: 'libexec/check-cron.sh',
              transform: relative_to(root_path)
    attribute :max_id_length, default: 16
    validates :_max_id_length, numericality: { only_integers: true }
    attribute :max_stdin_size, default: 1048576
    validates :_max_stdin_size, numericality: { only_integers: true }
    attribute :log_path, required: false,
              default: '~/.cache/flight/log/share/job.log',
              transform: ->(path) do
                if path
                  relative_to(root_path).call(path).tap do |full_path|
                    FileUtils.mkdir_p File.dirname(full_path)
                  end
                else
                  $stderr
                end
              end

    attribute :log_level, default: 'warn'
    # TODO: Replace with flight_ENVIRONMENT
    attribute :development, default: false, required: false
  end
end

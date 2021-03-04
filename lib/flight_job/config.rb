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
require 'xdg'
require 'fileutils'
require 'hashie'
require 'yaml'

require_relative 'errors'
require_relative 'version'

module FlightJob
  REFERENCE_PATH = File.expand_path('../../etc/config.reference', __dir__)
  CONFIG_PATH = File.expand_path('../../etc/config.yaml', __dir__)

  class Config < Hashie::Trash
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::Dash::IndifferentAccess

    def self.xdg
      @xdg ||= XDG::Environment.new
    end

    def self.load_reference(path)
      self.instance_eval(File.read(path), path, 0) if File.exists?(path)
    end

    def self.config(sym, **input_opts)
      opts = input_opts.dup

      # Make keys with defaults required by default
      opts[:required] = true if opts.key? :default && !opts.key?(:required)

      # Defines the underlining property
      property(sym, **opts)

      # Define the truthiness method as not empty and not nil
      define_method(:"#{sym}?") do
        value = send(sym)
        if value.respond_to?(:empty?)
          !value.empty?
        else
          !value.nil?
        end
      end
    end

    # Loads the config keys from the reference and adds the development key
    self.load_reference(REFERENCE_PATH)
    config :development

    # Ensures the token file exists
    def token
      if File.readable?(token_file)
        File.read(token_file)
      else
        raise CredentialsError, token_error
      end
    end

    # Defines the logging methods
    def log_path_or_stderr
      if log_level == 'disabled'
        '/dev/null'
      elsif log_path
        FileUtils.mkdir_p File.dirname(log_path)
        log_path
      else
        $stderr
      end
    end

    def logger
      @logger ||= Logger.new(log_path_or_stderr).tap do |log|
        next if log_level == 'disabled'

        # Determine the level
        level = case log_level
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

    def base_url_domain
      base_url.sub(/#{base_url_path}\Z/, '')
    end

    def base_url_path
      URI(base_url).path
    end
  end

  # Caches the config
  Config::CACHE = if File.exists? CONFIG_PATH
    data = File.read(CONFIG_PATH)
    Config.new(YAML.load(data, symbolize_names: true)).tap do |c|
      c.logger.info "Loaded Config: #{CONFIG_PATH}"
    end
  else
    Config.new({}).tap do |c|
      c.logger.info "Missing Config: #{CONFIG_PATH}"
    end
  end
end

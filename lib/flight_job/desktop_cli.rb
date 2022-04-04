#==============================================================================
# Copyright (C) 2022-present Alces Flight Ltd.
#
# This file is part of FlightJob.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# FlightJob is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with FlightJob. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on FlightJob, please visit:
# https://github.com/openflighthpc/flight-job
#===============================================================================

require 'etc'
require 'pathname'
require 'securerandom'
require 'flight/subprocess'

module FlightJob
  class DesktopCLI
    class << self
      def start_session(env:, script:)
        args = [
          "start",
          "--no-override-env",
          "--script", script,
          "--kill-on-script-exit",
        ]
        cmd = new(*flight_desktop, *args, env: env)
        if remote_host = select_remote_host(cmd.username)
          cmd.run_remote(remote_host)
        else
          cmd.run_local
        end.tap do |result|
          desktop_id = nil
          if result.success?
            result.stdout.split("\n").each do |line|
              key, value = line.split(/\t/, 2)
              if key == 'Identity'
                desktop_id = value
                break
              end
            end
          end
          result.define_singleton_method(:desktop_id) { desktop_id }
        end
      end

      private

      def select_remote_host(user)
        return nil if user == "root"
        Flight.config.remote_host_selector.call
      end

      def flight_desktop
        Flight.config.desktop_command
      end
    end

    def initialize(*cmd, user: nil, stdin: nil, timeout: nil, env: {})
      @timeout = timeout || Flight.config.command_timeout
      @cmd = cmd
      @user = user
      @stdin = stdin
      @env = {
        'PATH' => Flight.config.command_path,
        'HOME' => passwd.dir,
        'USER' => username,
        'LOGNAME' => username,
      }.merge(env)
    end

    def run_local(&block)
      Flight.logger.debug("Running subprocess (#{username}): #{@cmd.inspect}")
      process = Flight::Subprocess::Local.new(
        env: @env,
        logger: Flight.logger,
        timeout: @timeout,
      )
      result = process.run(@cmd, @stdin, &block)
      parse_result(result)
      log_command(result)
      result
    end

    def run_remote(host, &block)
      Flight.logger.debug("Running remote process (#{@user}@#{host}): #{@cmd.inspect}")
      public_key_path = Flight.config.ssh_public_key_path

      # HACK alert!
      # net/ssh which the Flight::Subprocess::Remote depends on has to be able
      # to find the Gemfile to determine whether optional dependencies are
      # installed or not.  Let's make sure that it can be found here.
      original = ENV['BUNDLE_GEMFILE']
      begin
        gemfile = File.expand_path(File.join(__FILE__, '../../../Gemfile'))
        ENV['BUNDLE_GEMFILE'] ||= gemfile
        Flight::Subprocess::Remote
      ensure
        ENV['BUNDLE_GEMFILE'] = original
      end

      process = Flight::Subprocess::Remote.new(
        connection_timeout: Flight.config.ssh_connection_timeout,
        env: @env,
        host: host,
        keys: [Flight.config.ssh_private_key_path],
        logger: Flight.logger,
        public_key_path: public_key_path,
        timeout: @timeout,
        username: @user,
      )
      result = process.run(@cmd, @stdin, &block)
      parse_result(result)
      log_command(result)
      result
    end

    def username
      @user || passwd.name
    end

    private

    def passwd
      @passwd ||= @user.nil? ? Etc.getpwuid : Etc.getpwnam(@user)
    end

    def parse_result(result)
      if result.exitstatus == 0 && expect_json_response?
        begin
          unless result.stdout.nil? || result.stdout.strip == ''
            result.stdout = JSON.parse(result.stdout)
          end
        rescue JSON::ParserError
          result.exitstatus = 128
        end
      end
    end

    def expect_json_response?
      @cmd.any? {|i| i.strip == '--json'}
    end

    def log_command(result)
      Flight.logger.info <<~INFO.chomp
        COMMAND: #{@cmd.inspect}
        USER: #{@user}
        PID: #{result.pid}
        STATUS: #{result.exitstatus}
      INFO
      Flight.logger.debug <<~DEBUG
        ENV:
        #{JSON.pretty_generate @env}
        STDIN:
        #{@stdin.to_s}
        STDOUT:
        #{result.stdout}
        STDERR:
        #{result.stderr}
      DEBUG
    end
  end
end

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

module FlightJob
  class DesktopCLI
    class << self
      def start_session(env:, script:)
        new(*flight_desktop, 'start', '--no-override-env', '--script', script, '--kill-on-script-exit', env: env).run_local
      end

      private

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
      Flight.logger.debug("Running subprocess (#{username}): #{stringified_cmd}")
      process = Subprocess.new(
        env: @env,
        logger: Flight.logger,
        timeout: @timeout,
      )
      result = process.run(@cmd, @stdin, &block)
      parse_result(result)
      log_command(result)
      result
    end

    private

    def username
      @user || passwd.name
    end

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
        COMMAND: #{stringified_cmd}
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

    def stringified_cmd
      @stringified_cmd ||= @cmd
        .map { |s| s.empty? ? '""' : s }.join(' ')
    end
  end
end

#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
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
require 'timeout'

module FlightJob
  class Subprocess
    class Result < Struct.new(:stdout, :stderr, :exitstatus, :pid)
      def success?
        exitstatus == 0
      end
    end

    def initialize(
      dir: nil,
      env:,
      logger:,
      supplementary_groups: false,
      timeout:,
      username: nil
    )
      @change_permissions = !!username
      @env = env
      @logger = logger
      @supplementary_groups = supplementary_groups
      @timeout = timeout
      @username = username
      @dir = dir || passwd.dir
    end

    def run(cmd, stdin, &block)
      @stdout = ""
      @stderr = ""
      @read_threads = []
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      create_pipes
      run_fork do
        run_command(cmd, &block)
      end
      start_read_threads
      write_stdin(stdin)
      status = wait_for_process
      wait_for_read_threads(start_time)
      exit_code = determine_exit_code(status)

      Result.new(@stdout, @stderr, exit_code, @pid)
    ensure
      close_pipes
    end

    private

    def run_fork(&block)
      @pid = Kernel.fork do
        @out_read.close
        @err_read.close
        @in_write.close
        change_permissions if @change_permissions
        Process.setsid
        block.call if block
      end
      @logger.debug("Forked process #{@pid.inspect}")
      @out_write.close
      @err_write.close
      @in_read.close
    end

    def change_permissions
      # Jump through hoops to 1) drop the parent process's group
      # permissions and 2) add all groups for user.
      Process.groups = []
      Process.gid = passwd.gid
      Process.egid = passwd.gid
      if @supplementary_groups
        Process.initgroups(@username, passwd.gid)
      end
      Process.uid = passwd.uid
      Process.euid = passwd.uid
    end

    def run_command(cmd, &block)
      block.call(@out_write, @err_write) if block
      if cmd.nil?
        @logger.debug("Nothing to exec")
        return
      end

      opts = {
        unsetenv_others: true,
        close_others: true,
        chdir: @dir,
        out: @out_write,
        err: @err_write,
        in: @in_read,
      }
      @logger.debug("Execing cmd")
      Kernel.exec(@env, *cmd, **opts)
    end

    def passwd
      @_passwd ||= @username.nil? ? Etc.getpwuid : Etc.getpwnam(@username)
    end

    def start_read_threads
      [ [@out_read, @stdout], [@err_read, @stderr] ].each do |io, buffer|
        @read_threads << Thread.new do
          begin
            loop { buffer << io.readpartial(1024) }
          rescue IOError
            # NOOP - Both EOF and IO closed errors need to be caught
          end
        end
      end
    end

    def write_stdin(stdin)
      return if stdin.nil?
      # We assume here that stdin is small enough to not cause an issue.  The
      # process and the read threads have been started so we should be OK with
      # that assumption.
      @in_write.write(stdin)
    end

    def wait_for_process
      signal = 'TERM'
      timeout = @timeout
      begin
        @logger.debug("Waiting for pid: #{@pid} for #{timeout} seconds")
        Timeout.timeout(timeout) do
          Process.wait(@pid)
        end
      rescue Timeout::Error
        @logger.info("Sending #{signal} to #{@pid}")
        Process.kill(-Signal.list[signal], @pid)
        signal = 'KILL'
        timeout = 1
        retry
      end
      $?
    end

    def determine_exit_code(status)
      if status.signaled?
        signame = Signal.signame(status.termsig)
        @logger.debug("Inferring exit code from signal #{signame} (pid: #{@pid})")
        status.termsig + 128
      elsif status.exitstatus
        status.exitstatus
      else
        @logger.debug("No exit code provided (pid: #{@pid})")
        128
      end
    end

    # Wait for the remaining timeout for the read threads to finish.  Kill any
    # threads still alive after the timeout has expired.
    #
    # As the subprocess has completed, we would usually expect that the pipes
    # are closed and the next reads will read any remaining data.  There are
    # some circumstances, involving zombie grandchild processes, where that
    # might not be the case.
    #
    # We allow the threads any remaining timeout to complete reading the
    # pipes.  After that we kill the threads.
    def wait_for_read_threads(start_time)
      loop do
        break if @read_threads.none?(&:alive?)

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        remaining = @timeout + start_time - now
        break unless remaining > 0

        living_thread = @read_threads.select(&:alive?).first
        # Guard against potential race condition.
        living_thread.join(remaining) unless living_thread.nil?
      end

      @read_threads.select(&:alive?).map(&:kill)
    end

    def create_pipes
      @out_read, @out_write = IO.pipe
      @err_read, @err_write = IO.pipe
      @in_read,  @in_write  = IO.pipe
    end

    def close_pipes
      @out_read.close  if @out_read  && !@out_read.closed?
      @out_write.close if @out_write && !@out_write.closed?
      @err_read.close  if @err_read  && !@err_read.closed?
      @err_write.close if @err_write && !@err_write.closed?
      @in_read.close   if @in_read   && !@in_read.closed?
      @in_write.close  if @in_write  && !@in_write.closed?
    end
  end
end

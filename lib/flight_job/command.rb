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

require 'ostruct'
require 'pastel'
require 'tty-editor'

require 'stringio'

module FlightJob
  class Command
    attr_accessor :args, :opts

    def self.new_editor(pastel)
      cmd = TTY::Editor.from_env.first || begin
        $stderr.puts pastel.red <<~WARN.chomp
          Defaulting to 'vi' as the editor.
          This can be changed by setting the EDITOR environment variable.
        WARN
        'vi'
      end
      TTY::Editor.new(command: cmd)
    end

    def initialize(args, opts)
      @args = args.freeze
      @opts = opts
    end

    def run!
      FlightJob.logger.info "Running: #{self.class}"
      run
      FlightJob.logger.info 'Exited: 0'
    rescue => e
      if e.respond_to? :exit_code
        FlightJob.logger.fatal "Exited: #{e.exit_code}"
      else
        FlightJob.logger.fatal 'Exited non-zero'
      end
      FlightJob.logger.debug e.backtrace.reverse.join("\n")
      FlightJob.logger.error "(#{e.class}) #{e.message}"
      raise e
    end

    def run
      raise NotImplementedError
    end

    def pastel
      @pastel ||= Pastel.new
    end

    Pager = Struct.new(:retry_file, :follow, :pastel) do
      def page(text = nil, path: nil)
        if path
          open_path(path) { |io| page_io(io) }
        else
          IO.pipe do |read, write|
            write.write(text.to_s)
            write.close
            page_io(read)
          end
        end
      end

      private

      def open_path(path)
        # Wait for the file to become available with --retry
        if retry_file && !File.exist?(path)
          $stderr.puts pastel.yellow("Waiting for: #{path}")
          sleep 1 until File.exist?(path)
        elsif !File.exist?(path)
          return false
        end

        File.open(path) do |io|
          yield io if block_given?
        end

        return true
      end

      def page_io(io)
        # Determines the command
        cmd = if follow
                'less -S +F -Ps"Press h for help, F to follow, or q to quit"'
              elsif ['less', nil].include?(ENV['PAGER'])
                'less -SFRX -Ps"Press h for help or q to quit"'
              else
                ENV['PAGER']
              end

        # Manually pages the file to allow following
        # Disable interrupt!
        # The process is now controlled by the pager
        trap('SIGINT', 'IGNORE')
        pid = Kernel.spawn(cmd, in: io, out: $stdout)
        Process.wait pid
      ensure
        trap('SIGINT', 'DEFAULT')
      end
    end

    def pager
      @pager ||= Pager.new(opts.F || opts.retry, opts.F || opts.follow, pastel)
    end

    # Check if the given option flag denotes STDIN
    def stdin_flag?(flag)
      ['@-', '@/dev/stdin'].tap { |a| a << '@/proc/42/fd/0' if Process.pid == 42 }
                           .include? flag
    end

    # Ensures the file exists before reading
    def read_file(path)
      if File.exist?(path)
        File.read(path)
      else
        raise InputError, "Could not locate file: #{path}"
      end
    end

    # Allows multiple reads of STDIN without having to rewind it OR it being blocked indefinitely
    def cached_stdin
      @cached_stdin ||= $stdin.read_nonblock(FlightJob.config.max_stdin_size).tap do |str|
        if str.length == FlightJob.config.max_stdin_size
          raise InputError, "The STDIN exceeds the maximum size of: #{FlightJob.config.max_stdin_size}B"
        end
      end
    rescue Errno::EWOULDBLOCK, EOFError
      raise InputError, "Failed to read the data from the standard input"
    end

    def new_editor
      self.class.new_editor(pastel)
    end

    def render_output(klass, data)
      if opts.json
        json = data.as_json
        output_options[:interactive] ? JSON.pretty_generate(json) : JSON.dump(json)
      else
        klass.render(*data, **output_options)
      end
    end

    def output_options
      @output_options ||= {
        verbose: (opts.verbose ? true : nil),
        ascii: (opts.ascii ? true : nil),
        humanize: (opts.ascii || opts.pretty || $stdout.tty? ? true : nil)
      }
    end

    def load_template(name_or_id)
      template = Template.new(id: name_or_id)
      if template.exists?
        unless template.valid?
          FlightJob.logger.error("Failed to load invalid template: #{template.id}")
          FlightJob.logger.warn(template.errors.full_messages.join("\n"))
          raise InternalError, <<~ERROR.chomp
            Cannot load invalid template: #{template.id}
          ERROR
        end
        return template
      end

      templates = Template.load_all

      # Finds by ID if there is a single integer argument
      if name_or_id.match?(/\A\d+\Z/)
        # Corrects for the 1-based numbering
        index = name_or_id.to_i - 1
        if index < 0 || index >= templates.length
          raise MissingTemplateError, <<~ERROR.chomp
            Could not locate a template with index: #{name_or_id}
          ERROR
        end
        templates[index].tap do |template|
          unless template.valid?
            FlightJob.logger.error("Failed to load invalid template: #{template.id}")
            FlightJob.logger.warn(template.errors.full_messages.join("\n"))
            raise InternalError, <<~ERROR
              Cannot load the following template as it is invalid: #{template.id}
            ERROR
          end
        end

      else
        # Attempts a did you mean?
        regex = /#{name_or_id}/
        matches = templates.select { |t| regex.match?(t.id) }
        if matches.empty?
          raise MissingTemplateError, "Could not locate: #{name_or_id}"
        else
          output = render_output(Outputs::ListTemplates, *matches)
          raise MissingTemplateError, <<~ERROR.chomp
            Could not locate: #{name_or_id}. Did you mean one of the following?
            #{Paint[output, :reset]}
          ERROR
        end
      end
    end

    def load_script(id)
      Script.new(id: id).tap do |script|
        unless script.exists?
          raise MissingScriptError, "Could not locate script: #{id}"
        end
        unless script.valid?(:load)
          FlightJob.logger.error("Failed to load script: #{id}\n") do
            script.errors.full_messages
          end
          raise InternalError, "Unexpectedly failed to load script: #{id}"
        end
      end
    end

    def load_job(id)
      Job.new(id: id).tap do |job|
        unless File.exist?(job.metadata_path)
          raise MissingJobError, "Could not locate job: #{id}"
        end
        if job.valid?
          job.monitor
        else
          FlightJob.logger.error("Invalid job: #{id}\n") do
            job.errors.full_messages
          end
        end
      end
    end

    def assert_results_dir_exists(job, allow_empty: true)
      error = if !job.results_dir
                true
              elsif !Dir.exists?(job.results_dir)
                true
              elsif allow_empty
                false
              elsif Dir.empty?(job.results_dir)
                true
              else
                false
              end
      return unless error

      case job.state
      when 'PENDING'
        raise MissingError, 'Your job has not started, please try again later...'
      when *Job::RUNNING_STATES
        raise MissingError, 'No job results found, please try again later...'
      else
        raise MissingError, 'No job results found.'
      end
    end
  end
end

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
require_relative 'configuration'
require_relative 'version'

require 'commander'
require_relative 'help_formatter'

module FlightJob
  module CLI
    extend Commander::CLI

    def self.create_command(name, args_str = '')
      command(name) do |c|
        c.syntax = "#{program :name} #{name} #{args_str}"
        c.hidden if name.split.length > 1

        c.action do |args, opts|
          require_relative '../flight_job'
          begin
            const_string = FlightJob.constantize(c.name)
            command = FlightJob::Commands.const_get(const_string).new(args, opts)
          rescue NameError
            FlightJob.logger.fatal "Command class not defined (maybe?): FlightJob::Commands::#{const_string}"
            raise InternalError.define_class(127), 'Command Not Found!'
          end
          command.run!
        end

        yield c if block_given?
      end
    end

    program :name,         ENV.fetch('FLIGHT_PROGRAM_NAME') { 'bin/job' }
    program :application,  'Flight Job'
    program :description,  'Generate and submit jobs from predefined templates'
    program :version, "v#{FlightJob::VERSION}"
    program :help_paging, false
    default_command :help

    # NOTE: There is a bug in Commander where the help formatter aliases aren't set
    @help_formatter_aliases = {}
    program :help_formatter, HelpFormatter

    if [/^xterm/, /rxvt/, /256color/].all? { |regex| ENV['TERM'] !~ regex }
      Paint.mode = 0
    end

    global_slop.bool '--verbose', 'Display additional details, when supported'
    global_slop.bool '--pretty', 'Display a human friendly output, when supported'
    global_slop.bool '--ascii', 'Display a simplified version of the output, when supported'
    global_slop.bool '--json', 'Display a JSON version of the output, when supported'

    # NOTE: NEXT MAJOR CLI RELEASE
    # Please review the Outputs and <Model>#serializable_hash methods on the next major release
    # These will need simplifying

    create_command 'list-templates' do |c|
      c.summary = 'List available templates'
      c.description = <<~DESC.chomp
      List available templates.
      
      Filter the displayed templates using the optional flags. Filters may be input as 
      glob expressions. Filters that include wildcards or spaces should be enclosed in 
      quotes.

      Multiple comma-separated filter expressions may be passed to each flag. A template 
      is considered to have passed the filter for a given flag if its attributes 
      match at least one of these expressions.
      DESC
      c.slop.string '--id', 'Filter by template ID', meta: 'ID[,ID...]'
      c.slop.string '--name', 'Filter by template name', meta: 'NAME[,NAME...]'
    end

    create_command 'copy-template', 'NAME [DEST]' do |c|
      c.summary = 'Generate a local version of a template'
    end

    create_command 'info-template', 'NAME' do |c|
      c.summary = 'Display details about a template'
    end

    create_command 'list-scripts' do |c|
      c.summary = 'List your rendered scripts'
      c.description = <<~DESC.chomp
      List your rendered scripts.
      
      Filter the displayed scripts using the optional flags. Filters may be input as 
      glob expressions; filters with wildcards should be enclosed in quotes.

      Multiple comma-separated filter expressions may be passed to each flag. A script 
      is considered to have passed the filter for a given flag if its attributes 
      match at least one of these expressions.
      DESC
      c.slop.string '--id', 'Filter by script ID', meta: 'ID[,ID...]'
      c.slop.string '--template', 'Filter by template ID', meta: 'TEMPLATE[,TEMPLATE...]'
    end

    create_command 'view-script', 'SCRIPT_ID' do |c|
      c.summary = 'View the content of a script'
    end

    create_command 'info-script', 'SCRIPT_ID' do |c|
      c.summary = 'Display details about a rendered script'
    end

    create_command 'create-script', 'TEMPLATE_NAME [SCRIPT_ID]' do |c|
      c.summary = 'Render a new script from a template'
      c.slop.string '--answers', <<~MSG.chomp, meta: 'JSON|@filepath|@-'
        Provide the answers as a JSON string.
        Alternatively specify a file containing the JSON answers with @filepath or STDIN as @-
      MSG
      c.slop.string '--notes', <<~MSG.chomp, meta: 'NOTES|@filepath|@-'
        Provide additional information about the script (Markdown formatting is supported).
        Alternatively specify a file containing the notes with @filepath or STDIN as @-
      MSG
      c.slop.bool '--stdin', 'Same as: "--answers @-"'
    end

    create_command 'edit-script', 'SCRIPT_ID' do |c|
      c.summary = 'Open the script in your editor'
      c.description = <<~DESC.chomp
        Edit your script.

        Open the script in the editor given by `$VISUAL`, `$EDITOR` or `vi`.

        Changes you make will affect any future jobs submitted from this script,
        but will not affect jobs already submitted.
      DESC
      c.slop.string '--content', <<~MSG.chomp, meta: '@filepath|@-'
        Provide the content without the use of the editor. The provided file will
        replace the existing version

        Files are specified as @filepath or STDIN as @-.
      MSG
      c.slop.boolean '--force', <<~MSG.chomp
        Skip the confirmation when using the --content flag
      MSG
    end

    create_command 'edit-script-notes', 'SCRIPT_ID' do |c|
      c.summary = 'Open the notes in your system editor'
      c.description = <<~DESC.chomp
        Edit your notes for a script.

        Open the notes in the editor given by `$VISUAL`, `$EDITOR` or `vi`.
      DESC
      c.slop.string '--notes', <<~MSG.chomp, meta: 'NOTES|@filepath|@-'
        Provide the notes without the use of the editor. The NOTES will replace
        the existing version.

        Alternatively specify a file containing the notes with @filepath or STDIN as @-
      MSG
    end

    create_command 'delete-script', 'SCRIPT_ID' do |c|
      c.summary = 'Permanently remove a script'
    end

    create_command 'list-jobs' do |c|
      c.summary = 'List your previously submitted jobs'
      c.description = <<~DESC.chomp
      List your previously submitted jobs.
      
      Filter the displayed jobs using the optional flags. Filters may be input as 
      glob expressions; filters with wildcards should be enclosed in quotes.

      Multiple comma-separated filter expressions may be passed to each flag. A job 
      is considered to have passed the filter for a given flag if its attributes 
      match at least one of these expressions.
      DESC
      c.slop.string '--id', 'Filter by job ID', meta: 'ID[,ID...]'
      c.slop.string '--script', 'Filter by script ID', meta: 'SCRIPT[,SCRIPT...]'
      c.slop.string '--state', "Filter by job state. Valid states include: \n" \
      'PENDING, RUNNING, COMPLETED, CANCELLED, FAILED, BROKEN, UNKNOWN', meta: 'STATE[,STATE...]'
    end

    # NOTE: Ideally the method signature would be: JOB_ID [-- LS_OPTIONS...]
    # but this isn't supported by Commander.
    #
    # Consider refactoring
    create_command 'list-job-results', 'JOB_ID [--] [LS_OPTIONS...]' do |c|
      c.summary = "Run the ls command within the job's results directory"
      c.description = <<~DESC.chomp
        Wraps the 'ls' utility within the job's results directory.

        Flags can be provided to 'ls' by specifying them after the
        '--' delimiter:

        #{program(:name)} list-job-results JOB_ID -- -laR
      DESC
    end

    create_command 'submit-job', 'SCRIPT_ID' do |c|
      c.summary = 'Schedule a new job to run from a script'
      c.slop.string '--answers', <<~MSG.chomp, meta: 'JSON|@filepath|@-'
        Provide the answers as a JSON string.
        Alternatively specify a file containing the JSON answers with @filepath or STDIN as @-
      MSG
      c.slop.bool '--stdin', 'Same as: "--answers @-"'
    end

    create_command 'info-job', 'JOB_ID' do |c|
      c.summary = 'Display details about a submitted job'
    end

    apply_follow_opts = ->(c) do
      c.slop.bool '-f','--follow', <<~DESC.chomp
        Append data to the pager as the file grows.
        This option ignores the PAGER env var and will use less.
      DESC
      c.slop.bool '-r', '--retry', <<~DESC.chomp
        Keep trying to open the file until it becomes available.
      DESC
      c.slop.bool '-F', 'Equivalent to: --follow --retry'
    end

    create_command 'view-job-results', 'JOB_ID FILENAME' do |c|
      c.summary = "View a file within the job's results directory"
      apply_follow_opts.call(c)
    end

    create_command 'view-job-stdout', 'JOB_ID' do |c|
      c.summary = "View the job's standard output"
      apply_follow_opts.call(c)
      c.action do |args, opts|
        require_relative '../flight_job'
        opts.type = :job_stdout
        FlightJob::Commands::ViewJobOutput.new(args, opts).run!
      end
    end

    create_command 'view-job-stderr', 'JOB_ID' do |c|
      c.summary = "View the job's standard error"
      apply_follow_opts.call(c)
      c.action do |args, opts|
        require_relative '../flight_job'
        opts.type = :job_stderr
        FlightJob::Commands::ViewJobOutput.new(args, opts).run!
      end
    end

    create_command 'cancel-job', 'JOB_ID' do |c|
      c.summary = 'Cancel the specified job'
    end

    create_command 'delete-job', 'JOB_ID' do |c|
      c.summary = 'Permanently remove the specified job'
      c.description = <<~DESC.chomp
      This will permanently remove Flight Job's record of the specified job.
      Flight Job will no longer be able to help you access the specified job's
      results.

      If a record is kept elsewhere such as the HPC scheduler's accouting
      database, that record will not be affected.
      DESC
    end

    create_command 'list-array-tasks', 'JOB_ID' do |c|
      c.summary = 'List all the tasks for an array job'
      c.description = <<~DESC.chomp
      List all the tasks for a previously submitted array job.
      
      Filter the displayed tasks by their current state using the optional 
      `--state` flag. Filters may be input as glob expressions; filters with 
      wildcards should be enclosed in quotes.

      Multiple comma-separated filter expressions may be passed to the `--state` 
      flag. A task is considered to have passed the filter if its state matches at
      least one of these expressions.
      DESC
      c.slop.string '--state', "Filter by task state. Valid states include: \n" \
      'PENDING, RUNNING, COMPLETING, COMPLETED, FAILED, CANCELLED, UNKNOWN', meta: 'STATE[,STATE...]'
    end

    create_command 'info-array-task', 'JOB_ID INDEX' do |c|
      c.summary = 'Display details about an array task'
    end

    create_command 'view-array-task-stdout', 'JOB_ID INDEX' do |c|
      c.summary = "View an array task's standard output"
      apply_follow_opts.call(c)
      c.action do |args, opts|
        require_relative '../flight_job'
        opts.type = :task_stdout
        FlightJob::Commands::ViewJobOutput.new(args, opts).run!
      end
    end

    create_command 'view-array-task-stderr', 'JOB_ID INDEX' do |c|
      c.summary = "View an array task's standard error"
      apply_follow_opts.call(c)
      c.action do |args, opts|
        require_relative '../flight_job'
        opts.type = :task_stderr
        FlightJob::Commands::ViewJobOutput.new(args, opts).run!
      end
    end

    create_command 'run-monitor' do |c|
      c.summary = 'Monitor the state of the jobs with the cluster scheduler'
      c.description = <<~DESC.chomp
        Flight Job maintains its own record about the jobs it submits to the
        HPC scheduler.  Under normal usage patterns it is expected that Flight
        Job will always be able to monitor the job until it either completes
        or fails in some way.  However, under some HPC scheduler
        configurations Flight Job may become unable to correctly update its
        records.

        If you find your jobs becoming stuck in an UNKNOWN state you will want
        to periodically run this command.
      DESC
    end

    create_command 'run-migration' do |c|
      c.summary = 'Migrate Flight Job data'
      c.description = <<~DESC.chomp
        Migrate the Flight Job data to the latest data format.  You will want
        to run this after Flight Job is updated.
      DESC
      c.action do
        require_relative '../flight_job_migration.rb'
        Flight.logger.info "Running: FlightJobMigration.migrate"
        FlightJobMigration.migrate
        Flight.logger.info 'Exited: 0'
      end
    end

    alias_command 'create', 'create-script'
    alias_command 'submit', 'submit-job'
    alias_command 'cp',     'copy-template'
    alias_command 'copy',   'copy-template'
    alias_command 'ls-job-results', 'list-job-results'
    alias_command 'list',   'list-jobs'
    alias_command 'info',   'info-job'

    alias_command 'list-tasks', 'list-array-tasks'
    alias_command 'info-task', 'info-array-task'
    alias_command 'view-task-stdout', 'view-array-task-stdout'
    alias_command 'view-task-stderr', 'view-array-task-stderr'

    if Flight.env.development?
      create_command 'console' do |c|
        c.action do |args, opts|
          require_relative 'command'
          require_relative '../flight_job'
          FlightJob::Command.new(args, opts).instance_exec { binding.pry }
        end
      end
    end
  end
end

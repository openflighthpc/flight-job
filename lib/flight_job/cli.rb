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
            FlightJob.logger.fatal "Command class not defined (maybe?): #{self}::#{const_string}"
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

    create_command 'list-templates' do |c|
      c.summary = 'List available templates'
    end

    create_command 'copy-template', 'NAME [DEST]' do |c|
      c.summary = 'Generate a local version of a template'
    end

    create_command 'info-template', 'NAME' do |c|
      c.summary = 'Display details about a template'
    end

    create_command 'list-scripts' do |c|
      c.summary = 'List your rendered scripts'
    end

    create_command 'view-script', 'SCRIPT_ID' do |c|
      c.summary = 'View the content of a script'
    end

    create_command 'info-script', 'SCRIPT_ID' do |c|
      c.summary = 'Display details about a rendered script'
    end

    create_command 'create-script', 'TEMPLATE_NAME [SCRIPT_NAME]' do |c|
      c.summary = 'Render a new script from a template'
      c.slop.string '--answers', <<~MSG.chomp, meta: 'JSON|@filepath|@-'
        Provide the answers as a JSON string.
        Alternatively specify a file containing the answers with @filepath or STDIN as @-
      MSG
      c.slop.string '--notes', <<~MSG.chomp, meta: 'NOTES|@filepath|@-'
        Provide additional information about the script
        Alternatively specify a file containing the notes with @filepath or STDIN as @-
      MSG
      c.slop.bool '--stdin', 'Same as: "--answers @-"'
    end

    # NOTE: This method signature is weird! I would expect it to be:
    # rename-script OLD_SCRIPT_NAME, NEW_SCRIPT_NAME
    #
    # However this isn't possible as the "identity names" are not unique.
    # Consider collapsing the ID and "identity_name" to be the same thing
    create_command 'rename-script', 'SCRIPT_ID SCRIPT_NAME' do |c|
      c.summary = 'Rename a script given by its ID'
    end

    create_command 'edit-script-notes', 'SCRIPT_ID' do |c|
      c.summary = 'Open the script notes in the system editor'
    end

    create_command 'delete-script', 'SCRIPT_ID' do |c|
      c.summary = 'Permanently remove a script'
    end

    create_command 'list-jobs' do |c|
      c.summary = 'List your previously submitted jobs'
    end

    create_command 'run-monitor' do |c|
      c.summary = 'Update the internal state of the data cache'
    end

    create_command 'submit-job', 'SCRIPT_ID' do |c|
      c.summary = 'Schedule a new job to run from a script'
    end

    create_command 'info-job', 'JOB_ID' do |c|
      c.summary = 'Display details about a submitted job'
    end

    create_command 'delete-job', 'JOB_ID' do |c|
      c.summary = 'Permanently remove a job'
    end

    alias_command 'create', 'create-script'
    alias_command 'submit', 'submit-job'
    alias_command 'cp',     'copy-template'
    alias_command 'copy',   'copy-template'

    if FlightJob.config.development
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

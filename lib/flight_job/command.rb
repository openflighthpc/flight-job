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

module FlightJob
  class Command
    attr_accessor :args, :opts

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

    def output_options
      {
        verbose: (opts.verbose ? true : nil),
        ascii: (opts.ascii ? true : nil),
        interactive: (opts.ascii || $stdout.tty? ? true : nil),
        json: (opts.json ? true : nil)
      }
    end

    def load_template(name_or_id)
      template = Template.new(id: name_or_id)
      return template if template.valid?(:verbose)

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
        templates[index]

      else
        # Attempts a did you mean?
        regex = /#{name_or_id}/
        matches = templates.select { |t| regex.match?(t.id) }
        if matches.empty?
          raise MissingError, "Could not locate: #{name_or_id}"
        else
          output = Outputs::ListTemplates.build_output(**output_options).render(*matches)
          raise MissingError, <<~ERROR.chomp
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
        unless job.submitted?
          raise MissingJobError, "Could not locate job: #{id}"
        end
        unless job.valid?(:load)
          FlightJob.logger.error("Failed to load job: #{id}\n") do
            job.errors.full_messages
          end
          raise InternalError, "Unexpectedly failed to load job: #{id}"
        end
      end
    end
  end
end

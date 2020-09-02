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

require_relative 'template'
require_relative 'list_output'

module FlightJob
  class Command
    attr_accessor :args, :opts

    def initialize(*args, **opts)
      @args = args.freeze
      @opts = Hashie::Mash.new(opts)
    end

    def run!
      Config::CACHE.logger.info "Running: #{self.class}"
      run
      Config::CACHE.logger.info 'Exited: 0'
    rescue => e
      if e.respond_to? :exit_code
        Config::CACHE.logger.fatal "Exited: #{e.exit_code}"
      else
        Config::CACHE.logger.fatal 'Exited non-zero'
      end
      Config::CACHE.logger.debug e.backtrace.reverse.join("\n")
      Config::CACHE.logger.error "(#{e.class}) #{e.message}"
      raise e
    end

    def run
      raise NotImplementedError
    end

    def list_output
      @list_output ||= ListOutput.build_output(verbose: opts.verbose)
    end

    def load_template(name_or_id)
      templates = Template.load_all

      # Finds by ID if there is a single integer argument
      if name_or_id.match?(/\A\d+\Z/)
        # Corrects for the 1-based numbering
        index = name_or_id.to_i - 1
        if index < 0 || index >= templates.length
          raise MissingError, <<~ERROR.chomp
            Could not locate a template with index: #{name_or_id}
          ERROR
        end
        templates[index]

      # Handles an exact match
      elsif match = templates.find { |t| t.name == name_or_id }
        match

      else
        # Attempts a did you mean?
        regex = /#{name_or_id}/
        matches = templates.select { |t| regex.match?(t.name) }
        if matches.empty?
          raise MissingError, "Could not locate: #{name_or_id}"
        else
          raise MissingError, <<~ERROR.chomp
            Could not locate: #{name_or_id}. Did you mean one of the following?
            #{Paint[list_output.render(*matches), :reset]}
          ERROR
        end
      end
    end
  end
end

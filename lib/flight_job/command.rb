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

require 'faraday'
require 'faraday_middleware'

require_relative 'template'
require_relative 'list_templates_output'

require_relative 'records'

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

      if e.is_a?(Faraday::ConnectionFailed)
        raise GeneralError, 'Failed to establish a connection to the scheduler!'
      elsif e.is_a?(SimpleJSONAPIClient::Errors::NotFoundError) && e.response['content-type'] != 'application/vnd.api+json'
        raise GeneralError, <<~ERROR.chomp
          Received an unrecognised response from the upstream api!
          Please check the following configuration and try again: #{Paint["'base_url' and 'api_prefix'", :yellow]}
        ERROR
      elsif e.is_a?(SimpleJSONAPIClient::Errors::APIError) && e.response['content-type'] == 'application/vnd.api+json' && e.status < 500
        # Generic error handling of API requests. In general these errors should
        # be caught before here. However this is a useful fallback
        raise ClientError, <<~ERROR.chomp
          An error has occurred during your request:
          #{e.message}
        ERROR
      elsif e.is_a?(SimpleJSONAPIClient::Errors::APIError)
        raise ServerError, <<~ERROR.chomp
          An unexpected error has occurred during your request!
          Please contact your system administrator for further assistance.
        ERROR
      else
        raise e
      end
    end

    def run
      raise NotImplementedError
    end

    def faraday_options
      {
        url: Config::CACHE.base_url_domain,
        ssl: { verify: Config::CACHE.verify_ssl },
        headers: {
          'Content-Type' => 'application/vnd.api+json',
          'Accept' => 'application/vnd.api+json',
          'Authorization' => "Bearer #{Config::CACHE.token}"
        }
      }
    end

    def connection
      @connection ||= Faraday.new(**faraday_options) do |c|
        c.use Faraday::Response::Logger, Config::CACHE.logger, { bodies: true } do |l|
          l.filter(/(Authorization:)(.*)/, '\1 [REDACTED]')
        end
        c.request :json
        c.response :json, :content_type => /\bjson$/
        c.adapter :net_http
      end
    end

    def request_template_questions(id)
      url = File.join(TemplatesRecord::INDIVIDUAL_URL % { id: id }, 'questions')
      QuestionsRecord.fetch_all(connection: connection, url: url).to_a
    end

    def request_templates
      TemplatesRecord.fetch_all(connection: connection)
                     .sort_by(&:name)
                     .tap do |templates|
        templates.each_with_index do |template, idx|
          template.index = idx + 1
        end
      end
    end

    def request_template(id)
      TemplatesRecord.fetch(connection: connection, url_opts: { id: id })
    end

    def request_scripts
      ScriptsRecord.fetch_all(connection: connection, includes: ['template'])
    end

    def output_mode_options
      {
        verbose: (opts.verbose ? true : nil),
        ascii: (opts.ascii ? true : nil),
        interactive: (opts.ascii ? true : nil),
        row_color: :cyan,
        header_color: :bold
      }
    end

    def list_templates_output
      @list_templates_output ||= ListTemplatesOutput.build_output(**output_mode_options)
    end

    def load_template(id_or_index)
      begin
        return request_template(id_or_index)
      rescue SimpleJSONAPIClient::Errors::NotFoundError
        # NOOP
      end
      templates = request_templates

      # Finds by ID if there is a single integer argument
      if id_or_index.match?(/\A\d+\Z/)
        # Corrects for the 1-based numbering
        index = id_or_index.to_i - 1
        if index < 0 || index >= templates.length
          raise MissingError, <<~ERROR.chomp
            Could not locate a template with index: #{id_or_index}
          ERROR
        end
        templates[index]

      else
        # Attempts a did you mean?
        regex = /#{id_or_index}/
        matches = templates.select { |t| regex.match?(t.name) }
        if matches.empty?
          raise MissingError, "Could not locate: #{id_or_index}"
        else
          raise MissingError, <<~ERROR.chomp
            Could not locate: #{id_or_index}. Did you mean one of the following?
            #{Paint[list_templates_output.render(*matches), :reset]}
          ERROR
        end
      end
    end
  end
end

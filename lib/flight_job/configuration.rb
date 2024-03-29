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

require 'i18n/backend'

require 'active_model'

require 'flight_configuration'
require_relative 'errors'

module FlightJob
  class ConfigError < InternalError; end

  class Configuration
    include FlightConfiguration::DSL
    include FlightConfiguration::RichActiveValidationErrorMessage
    include ActiveModel::Validations

    application_name 'job'

    user_configs :jobs_dir,
      :log_level,
      :log_path,
      :minimum_terminal_width,
      :scripts_dir,
      :templates_dir

    attribute :templates_dir, default: 'usr/share/job/templates',
              transform: relative_to(root_path)
    validates :templates_dir, presence: true
    attribute :scripts_dir, default: '~/.local/share/flight/job/scripts',
              transform: relative_to(root_path)
    validates :scripts_dir, presence: true

    attribute :jobs_dir, default: '~/.local/share/flight/job/jobs',
              transform: relative_to(root_path)
    validates :jobs_dir, presence: true

    attribute :scheduler, default: 'slurm'
    validates :scheduler, presence: true

    attribute :additional_paths, default: '',
              transform: ->(paths) { paths.empty? || paths[0] == ':' ? paths : ":#{paths}" }

    attribute :desktop_command,
      default: File.join(ENV.fetch('flight_ROOT', '/opt/flight'), 'bin/flight desktop'),
      transform: ->(value) { value.split(' ') }
    validates :desktop_command, presence: true
    validate { is_array(:desktop_command) }

    attribute :command_timeout, default: 30,
      transform: :to_f
    validates :command_timeout, numericality: true, allow_blank: false

    attribute :submit_script_path,
              default: ->(config) { File.join('libexec/job', config.scheduler, 'submit.sh') },
              transform: relative_to(root_path)
    validates :submit_script_path, presence: true

    attribute :bootstrap_script_path,
              default: ->(config) { File.join('libexec/job', config.scheduler, 'bootstrap.sh') },
              transform: relative_to(root_path)
    validates :bootstrap_script_path, presence: true

    attribute :cancel_script_path,
              default: ->(config) { File.join('libexec/job', config.scheduler, 'cancel.sh') },
              transform: relative_to(root_path)
    validates :cancel_script_path, presence: true

    attribute :monitor_script_path,
              default: ->(config) { File.join('libexec/job', config.scheduler, 'monitor.sh') },
              transform: relative_to(root_path)
    validates :monitor_script_path, presence: true

    attribute :monitor_array_script_path,
              default: ->(config) { File.join('libexec/job', config.scheduler, 'monitor-array.sh') },
              transform: relative_to(root_path)
    validates :monitor_array_script_path, presence: true

    attribute :adapter_script_path,
              default: ->(config) { File.join("usr/share/job/adapter.#{config.scheduler}.erb") },
              transform: relative_to(root_path)

    attribute :submission_period, default: 300
    validates :submission_period, numericality: { only_integers: true }

    attribute :minimum_terminal_width, default: 80
    validates :minimum_terminal_width, numericality: { only_integers: true }

    attribute :max_id_length, default: 16
    validates :max_id_length, numericality: { only_integers: true, greater_than: 5 }

    attribute :id_generation_attempts, default: 1_000_000
    validates :id_generation_attempts, numericality: { only_integers: true, greater_than: 0 }

    attribute :max_stdin_size, default: 1048576
    validates :max_stdin_size, numericality: { only_integers: true }

    attribute :includes, default: '', transform: ->(v) { v.to_s.split(',') }
    validates :includes, presence: true, allow_blank: true

    attribute :remote_hosts, default: [],
      transform: ->(v) { v.is_a?(Array) ? v : v.to_s.split }
    validate { is_array(:remote_hosts) }

    attribute :ssh_connection_timeout, default: 5,
      transform: :to_i
    validates :ssh_connection_timeout, numericality: { greater_than: 0 }, allow_blank: false

    attribute :ssh_private_key_path, default: "etc/job/id_rsa",
      transform: relative_to(root_path)
    validates :ssh_private_key_path, presence: true
    # XXX Validate that the path exists and is readable.
    attribute :ssh_public_key_path, default: "etc/job/id_rsa.pub",
      transform: relative_to(root_path)
    validates :ssh_public_key_path, presence: true

    attribute :log_path, required: false,
              default: '~/.cache/flight/log/share/job.log',
              transform: ->(path) do
                if path
                  relative_to(root_path).call(path).tap do |full_path|
                    FileUtils.mkdir_p File.dirname(full_path)
                  end
                else
                  $stderr
                end
              end

    attribute :log_level, default: 'warn'
    validates :log_level, inclusion: {
      within: %w(fatal error warn info debug disabled),
      message: 'must be one of fatal, error, warn, info, debug or disabled'
    }

    def join_schema_path(basename)
      File.expand_path(
        File.join('../../config/schemas/job', basename),
        __dir__
      )
    end

    def job_schema_path
      join_schema_path('version2.json')
    end

    def directives_name
      "directives.#{scheduler}.erb"
    end

    def command_path
      ENV['PATH'] + Flight.config.additional_paths
    end

    def remote_host_selector
      @_remote_host_selector ||= RemoteHostSelector.new(remote_hosts)
    end

    private

    def is_array(attr)
      value = send(attr)
      errors.add(attr, "must be an array") unless value.is_a?(Array)
    end
  end
end

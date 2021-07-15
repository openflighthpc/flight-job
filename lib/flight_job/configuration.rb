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
    extend FlightConfiguration::DSL
    include FlightConfiguration::RichActiveValidationErrorMessage
    include ActiveModel::Validations

    application_name 'job'

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

    attribute :state_map_path,
              default: ->(config) { File.join("etc/job/state-maps", "#{config.scheduler}.yaml") },
              transform: relative_to(root_path)
    validates :state_map_path, presence: true

    attribute :submit_script_path,
              default: ->(config) { File.join('libexec/job', config.scheduler, 'submit.sh') },
              transform: relative_to(root_path)
    validates :submit_script_path, presence: true

    attribute :monitor_script_path,
              default: ->(config) { File.join('libexec/job', config.scheduler, 'monitor.sh') },
              transform: relative_to(root_path)
    validates :monitor_script_path, presence: true

    attribute :submission_period, default: 3600
    validates :submission_period, numericality: { only_integers: true }

    attribute :minimum_terminal_width, default: 80
    validates :minimum_terminal_width, numericality: { only_integers: true }

    attribute :max_id_length, default: 16
    validates :max_id_length, numericality: { only_integers: true }

    attribute :max_stdin_size, default: 1048576
    validates :max_stdin_size, numericality: { only_integers: true }

    attribute :includes, default: '', transform: ->(v) { v.to_s.split(',') }
    validates :includes, presence: true, allow_blank: true

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

    # NOTE: The directives_name doesn't need to be configurable (currently?)
    #       However the config is required to generate it, so it is best
    #       located here.
    def directives_name
      "directives.#{scheduler}.erb"
    end
  end
end

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
  class Configuration
    extend FlightConfiguration::DSL

    include ActiveModel::Validations

    # Duplicated from flight_configuration, consider porting back
    def self.load2(&block)
      new.tap do |config|
        # Merge in the sources
        merge_sources(config)

        # Run all the transform functions
        attributes.each { |k, _| config.send(k) }

        # Apply the default validators
        config.__sources__.each do |key, source|
          required = attributes.fetch(key, {})[:required]
          if source.value.nil? && required
            if active_errors?
              config.errors.add(key, :required, message: 'is required')
            else
              raise Error, "The required config has not been provided: #{key}"
            end
          elsif !attributes.key?(key)
            source.unrecognized = true
          end
          config.__logs__.set_from_source(key, source)
        end

        # Attempt to validate the config
        validate_config(config)
      end
    rescue => e
      raise e, "Cannot continue as the configuration is invalid:\n#{e.message}", e.backtrace
    end

    # NOTE: The defaults must not be applied until after all the config sources have been
    # set. This is to allow the default function to reference other sources.
    #
    # In practice, this means *_before_type_cast needs to call the default function
    def self.defaults
      attributes.map { |k, props| [k, props[:default]] }.to_h
    end

    application_name 'job'

    attribute :templates_dir, default: 'usr/share',
              transform: relative_to(root_path)
    attribute :scripts_dir, default: '~/.local/share/flight/job/scripts',
              transform: relative_to(root_path)
    attribute :jobs_dir, default: '~/.local/share/flight/job/jobs',
              transform: relative_to(root_path)

    attribute :scheduler, default: 'slurm'
    attribute :state_map_path,
              default: ->(config) { "etc/state-maps/#{config.scheduler}.yaml" },
              transform: relative_to(root_path)
    attribute :submit_script_path,
              default: ->(config) { File.join('libexec', config.scheduler, 'submit.sh') },
              transform: relative_to(root_path)
    attribute :monitor_script_path,
              default: ->(config) { File.join('libexec', config.scheduler, 'monitor.sh') },
              transform: relative_to(root_path)

    attribute :submission_period, default: 3600
    validates :submission_period, numericality: { only_integers: true }

    attribute :minimum_terminal_width, default: 80
    validates :minimum_terminal_width, numericality: { only_integers: true }

    attribute :check_cron, default: 'libexec/check-cron.sh',
              transform: relative_to(root_path)

    attribute :max_id_length, default: 16
    validates :max_id_length, numericality: { only_integers: true }

    attribute :max_stdin_size, default: 1048576
    validates :max_stdin_size, numericality: { only_integers: true }

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

    # Stores the transformed keys, the key denotes existence, allowing values
    # to be nil
    def __transformed__
      @__transformed__ ||= {}
    end

    attributes.each do |key, _|
      # Remove the accessor methods created by flight_configuration
      remove_method(key)
      remove_method("#{key}=")
      remove_method("#{key}_before_type_cast")

      # Redefine the *_before_type_cast to call the default method
      # NOTE: Consider moving this logic onto SourceStruct
      define_method("#{key}_before_type_cast") do
        source = __sources__[key]
        return nil unless source

        # Transform the default if required
        if source.type == :default && source.source.nil?
          # Repurpose source.source as a flag
          source.source = :transformed_default

          # Render the default
          value = if source.value.respond_to?(:call)
            if source.value.arity > 0
              # Provide the config
              source.value.call(self)
            else
              # Render without the config
              source.value.call
            end
          else
            source.value
          end

          # Cache the transformed value
          if [Hash, Array].any? { |c| value.is_a?(c) }
            source.value = FlightConfiguration::BaseDSL::DeepStringifyKeys.stringify(value)
          else
            source.value = value
          end

        # Else return whatever the value is
        else
          source.value
        end
      end

      # Redefine the accessors to preform the transform
      # NOTE: Should the accessors have access to the 'config'?
      #       This would allow user defined configs to perform a "transient transforms":
      #       e.g. ->(path, config) do
      #         Pathname.new(path).expand_path(root_path).gsub("$scheduler", config.scheduler)
      #       end
      #
      #       Whilst this looks appealing, it makes understanding and validating the
      #       config trickier. For the time being, it has been omitted.
      define_method(key) do
        if __transformed__.key?(key)
          __transformed__[key]
        else
          transform = self.class.attributes[key][:transform]
          original = self.send("#{key}_before_type_cast")

          # No transform
          __transformed__[key] = if transform.nil?
            original

          # Callable transform function
          elsif transform.respond_to?(:call)
            transform.call(original)

          # Short hand transform
          else
            original.send(transform)
          end
        end
      end

      # NOTE: The attr_write methods have not been redefined as they aren't used
      # in flight-job. In general, these methods need a re-think as their usage
      # does not work well with validation.
      #
      # Possible a better would be to run `load` again with a new "top level config"
      # e.g. load({ .. new top level configs .. })
      #
      # As these are the new top-level-configs, they are guaranteed to be validated.
      # The application can then safely save the configs at the correct level, be
      # that at the user or global level.
      #
      # This could lead to three config loads:
      #
      # 1. The initial load that sets Flight.config,
      # 2. The validation load with load({ ... new configs ... }) which is discarded, then
      # 3. Flight.config reload after saving the configs at the correct level. This may
      #    or may not override the new configs according to the config hierarchy. This
      #    step is optional depending on the new application. Otherwise it will occur
      #    when the application is ran again.
      #
      # *Technically* steps 1/2 could be valid, but result in an invalid config at step 3.
      # This can happen if the new hierarchy in step 3 results in a transient validation
      # dependency failure. In general, transient validations should be avoided as they
      # are hard to configure correctly. It is up to the application writer to avoid this.
    end
  end
end

#==============================================================================
## Copyright (C) 2021-present Alces Flight Ltd.
##
## This file is part of Flight Job.
##
## This program and the accompanying materials are made available under
## the terms of the Eclipse Public License 2.0 which is available at
## <https://www.eclipse.org/legal/epl-2.0>, or alternative license
## terms made available by Alces Flight Ltd - please direct inquiries
## about licensing to licensing@alces-flight.com.
##
## Flight Job is distributed in the hope that it will be useful, but
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
## IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
## OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
## PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
## details.
##
## You should have received a copy of the Eclipse Public License 2.0
## along with Flight Job. If not, see:
##
##  https://opensource.org/licenses/EPL-2.0
##
## For more information on Flight Job, please visit:
## https://github.com/openflighthpc/flight-job
##===========================================================================

require 'tempfile'

module FlightJobMigration
  module Jobs
    # Base class from which all job migrations should inherit.
    #
    # A subclass needs to define the methods: `migrate!`, `applicable?` and
    # `assert_new_metadata_valid`. More information on those methods can be
    # found in their definition in this class.
    class Base
      def self.load_all
        Dir.glob(File.join(Flight.config.jobs_dir, '*')).map do |dir|
          new(dir)
        end
      end

      def initialize(job_dir)
        @job_dir = job_dir
        @job_id = File.basename(@job_dir)
      end

      def migrate
        migrate!
        return true
      rescue
        Flight.logger.error "Failed to migrate job '#{@job_id}'"
        Flight.logger.debug $!
        return false
      end

      # Return true if the migration should run for this job.
      #
      # Typically a migration will examine `pre_metadata['version']` to
      # determine this.
      def applicable?
        raise NotImplementedError
      end

      private

      # Migrate the job from the previous version to the new.
      #
      # The job's metadata prior to it being migrated can be found at
      # `pre_metadata`.  The metadata returned by `pre_metadata` should be
      # considered read only.
      #
      # The `new_metadata` method starts as a copy of `pre_metadata`.  Any
      # chagnes to the metadata should be made to the hash returned by
      # `new_metadata`.
      def migrate!
        raise NotImplementedError
      end

      # Assert the metadata returned by `new_metadata` is valid; raise
      # MigrationError if not.
      #
      # Any errors should also be logged.
      def assert_new_metadata_valid
        raise NotImplementedError
      end

      # Return the metadata as it exists before the migration runs.
      #
      # This hash should not be modified.
      def pre_metadata
        return @pre_metadata if defined?(@pre_metadata)
        pm =
          if File.exist?(metadata_path)
            YAML.load(File.read(metadata_path))
          else
            {}
          end
        # Not quite a deep_freeze, but likely close enough for our needs.
        pm.each do |k,v|
          v.freeze
        end
        pm.freeze
        @pre_metadata = pm
      end

      # The new metadata for the job.  Changes to the metadata should be made
      # to the hash returned by this method.
      #
      # This starts as the pre_metadata and is expected to be changed before
      # being saved.
      #
      # If any pre-existing keys are no longer required, they can be deleted.
      def new_metadata
        @new_metadata ||= if File.exist?(metadata_path)
          YAML.load(File.read(metadata_path))
        else
          {}
        end
      end

      def increment_version
        new_metadata["version"] = pre_metadata["version"] + 1
      end

      # Write +new_metadata+ to the metadata file, making a backup of the
      # pre_metadata first.
      def save_metadata
        assert_new_metadata_valid
        File.write(backup_metadata_path, YAML.dump(pre_metadata))

        # Create the temp file in the same directory to ensure that
        # FileUtils.mv is atomic.
        Tempfile.open("metadata-migration", @job_dir) do |file|
          file.write(YAML.dump(new_metadata))
          file.rewind
          FileUtils.mv(file.path, metadata_path)
        end
      end

      def metadata_path
        File.join(@job_dir, 'metadata.yaml')
      end

      def backup_metadata_path
        File.join(@job_dir, ".metadata.v#{pre_metadata["version"]}.yaml")
      end
    end
  end
end

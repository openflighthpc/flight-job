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

require 'securerandom'

module FlightJob
  NameGenerator = Struct.new(:root_dir, :base, :previous_generator) do
    def self.new_script(base)
      new(FlightJob.config.scripts_dir, base)
    end

    def self.new_job(base)
      new(FlightJob.config.jobs_dir, base)
    end

    # Returns the base name if it is available AND short enough
    def base_name
      if File.exists? metadata_path(base)
        Flight.logger.debug("The base name '#{base}' has already been taken")
        nil
      elsif base.length > FlightJob.config.max_id_length
        Flight.logger.info("Reject base name '#{base}' as it is too long")
        nil
      else
        Flight.logger.info("Selecting base name '#{base}'")
        base
      end
    end

    def next_name
      candidate = "#{base}-#{next_index}"
      if candidate.length > FlightJob.config.max_id_length
        Flight.logger.info("Rejecting generated name '#{candidate}' as it is too long")
        new_generator(candidate)&.next_name || random_name
      else
        Flight.logger.info("Selecting next name '#{candidate}'")
        candidate
      end
    end

    def backfill_name
      candidate = "#{base}-#{backfill_index}"
      if candidate.length > FlightJob.config.max_id_length
        Flight.logger.info("Rejecting generated name '#{candidate}' as it is too long")
        new_generator(candidate)&.backfill_name || random_name
      else
        Flight.logger.info("Selecting backfilled name '#{candidate}'")
        candidate
      end
    end

    protected

    def next_index
      @next_index ||= begin
        idx = indices.empty? ? 1 : indices.last + 1
        idx > min_next_index ? idx : min_next_index
      end
    end

    def backfill_index
      @backfill_index ||= begin
        # The following indices can not be used as they are below the minimum
        # They are injected into the backfilling algorithm as a means to ignore them
        # NOTE: Must be exclusive range
        min_indices = (0...min_backfill_index).to_a
        backfill_indices = [*min_indices, *indices].sort.uniq

        # Identifies the first missing index
        (0..(backfill_indices.length + 1)).find { |i| i != backfill_indices[i] }
      end
    end

    private

    def random_name
      Flight.logger.info "Falling back on random name generation"
      (1..FlightJob.config.max_ids).each do
        candidate = SecureRandom.urlsafe_base64(6)
        return candidate unless File.exists? metadata_path(candidate)
      end
      raise InternalError, "Failed to generate a random name"
    end

    # Used to construct the next name generator with the base truncated
    # This is used to shorten the names when required
    #
    # NOTE: The candidate is the previously failed value
    #       It is used to determine how may characters need to be removed
    def new_generator(candidate)
      excess = candidate.length - Flight.config.max_id_length

      # Exit fast if the excess characters would result in empty string
      return nil if base.length <= excess

      # First attempt to strip any numbered prefixes
      new_base = base.sub(/-\d+\Z/, '')

      # Next, pop off the last characters
      if excess > (base.length - new_base.length)
        less = base.length - new_base.length - excess - 1
        new_base = new_base[0..less]
      end

      # Remove any trailing hypens
      new_base = new_base.sub(/-+\Z/, '')

      # Reject empty string
      return nil if new_base.empty?

      # Return the new name generator
      self.class.new(root_dir, new_base, self)
    end

    def indices
      Dir.glob(metadata_path("#{base}-*"))
        .map { |p| File.basename(File.dirname(p)) }
        .select { |n| /-\d+\Z/.match?(n) }
        .map { |n| n.split('-').last.to_i }
        .sort
        .uniq
    end

    def metadata_path(id)
      File.join(root_dir, id, 'metadata.yaml')
    end

    # Preserves the minimum index upon recursion
    def min_next_index
      previous_generator.nil? ? 1 : previous_generator.next_index
    end

    # Prevents backfilling if the index was already taken by a previous
    # longer base name
    def min_backfill_index
      previous_generator.nil? ? 1 : previous_generator.backfill_index
    end
  end
end

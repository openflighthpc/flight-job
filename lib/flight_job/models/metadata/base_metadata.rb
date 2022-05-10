#==============================================================================
# Copyright (C) 2022-present Alces Flight Ltd.
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

module FlightJob
  class Metadata
    # Base class providing common functionality for encapsulating
    # `metadata.yaml` files.
    #
    # * Loads and saves the file.
    # * Provides mechanism to register expected attributes and to get a list
    #   of expected attribute names.
    class BaseMetadata
      module AttributesConcern
        extend ActiveSupport::Concern

        included do
          class_attribute :attribute_names, instance_accessor: false
          self.attribute_names = []
        end

        module ClassMethods
          def attributes(*attrs, default: nil, reader: true, writer: true)
            attrs.each { |attr| attribute(attr, default: default, reader: reader, writer: writer) }
          end

          def attribute(attr, default: nil, reader: true, writer: true)
            if reader
              define_method(attr) do
                if @hash.is_a?(Hash)
                  @hash.fetch(attr.to_s, default)
                else
                  msg = "Attempting to read metadata attribute #{attr} but @hash is a #{@hash.class.name}"
                  Flight.logger.debug(msg)
                  nil
                end
              end
            end
            if writer
              define_method(:"#{attr}=") do |val|
                if @hash.is_a?(Hash)
                  @hash[attr.to_s] = val
                else
                  msg = "Attempting to set metadata attribute #{attr} but @hash is a #{@hash.class.name}"
                  Flight.logger.debug(msg)
                  nil
                end
              end
            end
            self.attribute_names << attr
          end
        end
      end

      include AttributesConcern
      include ActiveModel::Model

      attr_reader :path

      def self.load_from_path(path, parent)
        # XXX Handle Errno::ENOENT and Psych::SyntaxError errors here???
        md = YAML.load_file(path)
        new(md, path, parent)
      end

      def self.blank(path, parent)
        new({}, path, parent)
      end

      # Validates that the type of object loaded from the metadata file is of
      # the correct type, i.e., a Hash.
      validate on: :metadata_type do
        errors.add(:metadata, 'is not a hash') unless @hash.is_a?(Hash)
      end

      def [](attr)
        send(attr)
      end

      def []=(attr, val)
        send("#{attr}=", val)
      end

      def reload
        @hash = YAML.load_file(path)
      end

      def save
        if valid?
          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, YAML.dump(@hash))
        else
          parent_name = @parent.class.name.demodulize.downcase
          id = @parent.id
          Flight.logger.error("Failed to save #{parent_name} metadata: #{id}")
          Flight.logger.info(errors.full_messages.join("\n"))
          raise InternalError, "Unexpectedly failed to save #{parent_name} '#{id}' metadata"
        end
      end

      def to_hash
        @hash.deep_dup
      end

      private

      def initialize(hash, path, parent)
        @hash = hash
        @path = path
        @parent = parent
      end
    end
  end
end

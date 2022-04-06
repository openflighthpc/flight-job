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
  class MetadataBase
    module AttributesConcern
      extend ActiveSupport::Concern

      included do
        class_attribute :attribute_names, instance_accessor: false
        self.attribute_names = []
      end

      module ClassMethods
        def attributes(*attrs, default: nil)
          attrs.each { |attr| attribute(attr, default: default) }
        end

        def attribute(attr, default: nil)
          define_method(attr) { @hash.fetch(attr.to_s, default) }
          define_method(:"#{attr}=") { |val| @hash[attr.to_s] = val }
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
      if valid?(:save)
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

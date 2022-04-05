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

module FlightJob
  class ControlsDir
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def entries
      return [] unless exists?

      Dir.entries(@path)
        .select { |e| p = File.join(@path, e); File.file?(p) && File.readable?(p) }
        .map { |e| ControlsFile.new(self, e) }
    end

    def exists?
      File.exist?(@path)
    end

    def file(name)
      if exists?
        ControlsFile.new(self, name)
      else
        NullControlsFile.new(self, name)
      end
    end

    def serializable_hash
      Hash[entries.map { |file| [file.name, file.read] }]
    end
  end

  class ControlsFile
    attr_reader :name, :path

    def initialize(dir, name)
      @name = name
      @path = File.join(dir.path, name)
    end

    def exists?
      File.exist?(@path)
    end

    def read
      return nil unless exists?
      File.read(@path).force_encoding('UTF-8').strip
    end

    def write(content)
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, content)
    end
  end

  class NullControlsFile
    def initialize(dir, name)
      @path = File.join(dir.path, name)
    end

    def exists?
      false
    end

    def read
      nil
    end

    def write(content)
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, content)
    end
  end
end

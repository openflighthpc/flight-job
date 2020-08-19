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

require_relative 'command'

module FlightJob
  module Commands
    def self.constantize(sym)
      sym.to_s.dup.split(/[-_]/).each { |c| c[0] = c[0].upcase }.join
    end

    def self.build(s, *args, **opts)
      const_string = constantize(s)
      const_get(const_string).new(*args, **opts)
    rescue NameError
      Config::CACHE.logger.fatal "Command class not defined (maybe?): #{self}::#{const_string}"
      raise InternalError, 'Command Not Found!'
    end

    Dir.glob(File.expand_path('commands/*.rb', __dir__)).each do |file|
      autoload constantize(File.basename(file, '.*')), file
    end
  end
end

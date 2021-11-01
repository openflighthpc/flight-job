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
  module QuestionGenerators
    Dir.glob(File.expand_path('question_generators/*.rb', __dir__)).each do |path|
      autoload FlightJob.constantize(File.basename(path, '.*')), path
    end

    class << self
      def call(type:, **opts)
        generator(type, **opts).call
      end

      private

      def generator(type, **opts)
        const_string = FlightJob.constantize(type)
        FlightJob::QuestionGenerators.const_get(const_string).new(**opts)
      rescue NameError
        FlightJob.logger.fatal "Unknown option generator #{type}"
        raise InternalError, "Unknown option generator #{type}"
      end
    end
  end
end
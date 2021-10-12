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

require 'output_mode'

module FlightJob
  class Outputs::ListTemplates < OutputMode::Formatters::Index
    constructor do
      register(header: 'Index', row_color: :yellow) do |template|
        # NOTE: The OutputMode library does not support *_with_index type notation
        #       Instead the index needs to be cached on the object itself
        template.index
      end
      register(header: 'Name') do |template|
        template.id
      end
      file_header = "File (Dir: #{FlightJob.config.templates_dir})"

      if verbose?
        register(header: file_header) do |template|
          if interactive?
            Pathname.new(template.workload_path).relative_path_from FlightJob.config.templates_dir
          else
            template.workload_path
          end
        end
      end
    end
  end
end


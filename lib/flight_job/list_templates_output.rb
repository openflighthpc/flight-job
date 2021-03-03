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

require 'output_mode'

module FlightJob
  module ListTemplatesOutput
    # Defines a handy interface for generating Tabulated data
    extend OutputMode::TLDR::Index

    register_column(header: 'Index', row_color: :yellow) do |template|
      # NOTE: The OutputMode library does not supprt *_with_index type notation
      #       Instead the index needs to be cached on the object itself
      template.index
    end
    register_column(header: 'Name') do |template|
      template.name
    end
    register_column(header: "File (Dir: #{Config::CACHE.templates_dir})", verbose: true) do |template|
      if template.record
        template.metadata[:filename]
      elsif $stdout.tty?
        Pathname.new(template.path).relative_path_from Config::CACHE.templates_dir
      else
        template.path
      end
    end
  end
end

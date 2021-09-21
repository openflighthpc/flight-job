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
  module Outputs::ListArrayTasks
    extend OutputMode::TLDR::Index

    register_column(header: 'Index', row_color: :yellow, &:index)
    register_column(header: 'Job ID', &:job_id)
    register_column(header: 'State') { |t| t.metadata['state'] }

    register_column(header: 'Started at') do |task, verbose:|
      Outputs.format_time(task.metadata['start_time'], verbose)
    end
    register_column(header: 'Ended at') do |task, verbose:|
      Outputs.format_time(task.metadata['end_time'], verbose)
    end

    register_column(header: 'Estimated Start', verbose: true) { |t| t.metadata['estimated_start_time'] }
    register_column(header: 'Estimated Finish', verbose: true) { |t| t.metadata['estimated_end_time'] }

    register_column(header: 'StdOut Path', verbose: true) { |t| t.metadata['stdout_path'] }
    register_column(header: 'StdErr Path', verbose: true) { |t| t.metadata['stderr_path'] }

    def self.build_output(**opts)
      super(row_color: :cyan, header_color: :bold, **opts)
    end
  end
end

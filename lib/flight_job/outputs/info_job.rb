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
  module Outputs::InfoJob
    extend OutputMode::TLDR::Show

    register_attribute(header: 'ID') { |j| j.id }
    register_attribute(header: 'Script ID') { |j| j.script_id }
    register_attribute(header: 'Submitted') { |j| j.submit_status == 0 }
    register_attribute(header: 'State') { |j| j.state }

    # Toggle the format of the created at time
    register_attribute(header: 'Created At', verbose: true) { |j| j.created_at }
    register_attribute(header: 'Created At', verbose: false) do |job|
      DateTime.rfc3339(job.created_at).strftime('%d/%m %H:%M')
    end

    # NOTE: These could be the predicted times instead of the actual, consider
    # delineating the two
    register_attribute(header: 'Start Time', verbose: true) { |j| j.start_time }
    register_attribute(header: 'Start Time', verbose: false) do |job|
      next nil unless job.start_time
      DateTime.rfc3339(job.start_time).strftime('%d/%m %H:%M')
    end
    register_attribute(header: 'End Time', verbose: true) { |j| j.end_time }
    register_attribute(header: 'End Time', verbose: false) do |job|
      next nil unless job.end_time
      DateTime.rfc3339(job.end_time).strftime('%d/%m %H:%M')
    end

    def self.build_output(**opts)
      if opts.delete(:json)
        JSONRenderer.new(false, opts[:interactive])
      else
        super(**opts)
      end
    end
  end
end


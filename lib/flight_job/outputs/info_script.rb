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
  module Outputs::InfoScript
    extend OutputMode::TLDR::Show

    register_attribute(header: 'ID') { |s| s.id }
    register_attribute(header: 'Template ID') { |s| s.template_id }
    register_attribute(header: 'File Name') { |s| s.script_name }
    register_attribute(header: 'Path') { |s| s.script_path }


    # Toggle the format of the created at time
    register_attribute(header: 'Created At', verbose: true) { |s| s.created_at }
    register_attribute(header: 'Created At', verbose: false) do |script|
      DateTime.rfc3339(script.created_at).strftime('%d/%m/%y %H:%M')
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

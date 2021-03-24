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
  module Outputs::ListScripts
    extend OutputMode::TLDR::Index

    register_column(header: 'ID', row_color: :yellow) { |s| s.id }
    # NOTE: The verbose output is at the end to avoid the order changing
    register_column(header: 'Name', verbose: false) { |s| s.identity_name }
    register_column(header: 'Template ID') { |s| s.template_id }
    register_column(header: 'File Name') { |s| s.script_name }

    # Toggle the format of the created at time
    register_column(header: 'Created At', verbose: true) { |s| s.created_at }
    register_column(header: 'Created At', verbose: false) do |script|
      DateTime.rfc3339(script.created_at).strftime('%d/%m/%y %H:%M')
    end

    register_column(header: 'Path', verbose: true) { |s| s.script_path }

    # NOTE: The following is at the end to preserve the order of the verbose output
    register_column(header: 'Name', verbose: true) { |s| s.identity_name }

    def self.build_output(**opts)
      if opts.delete(:json)
        JSONRenderer.new(true, opts[:interactive])
      else
        super(row_color: :cyan, header_color: :bold, **opts).tap do |output|
          # NOTE: The rotate flag "hopefully" going to be a new feature to TTY::Table
          # that stops is rotating in small terminals. OutputMode has no concept of this
          # feature, currently
          output.config.merge!(rotate: false) if output.is_a? OutputMode::Outputs::Tabulated
        end
      end
    end
  end
end

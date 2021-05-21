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
  module Outputs::ListJobs
    extend OutputMode::TLDR::Index

    register_column(header: 'ID', row_color: :yellow) { |s| s.id }
    register_column(header: 'Script ID', verbose: true) { |j| j.script_id }
    register_column(header: 'Sched. ID', verbose: true) { |j| j.scheduler_id }
    register_column(header: 'State') { |j| j.state }

    # Show a boolean in the "simplified" output, and the exit code in the verbose
    # NOTE: The headers are intentionally toggled between outputs
    register_column(header: 'Submitted', verbose: false) { |j| j.submit_status == 0 }
    register_column(header: 'Submit Status', verbose: true) { |j| j.submit_status }

    register_column(header: 'Submitted at') do |job, verbose:|
      if verbose
        job.created_at
      else
        DateTime.rfc3339(job.created_at).strftime('%d/%m/%y %H:%M')
      end
    end

    # NOTE: These could be the predicted times instead of the actual, consider
    # delineating the two
    register_column(header: 'Started at') do |job, verbose:|
      if job.start_time.nil?
        nil
      elsif verbose
        job.start_time
      else
        DateTime.rfc3339(job.start_time).strftime('%d/%m/%y %H:%M')
      end
    end
    register_column(header: 'Ended at') do |job, verbose:|
      if job.end_time.nil?
        nil
      elsif verbose
        job.end_time
      else
        DateTime.rfc3339(job.end_time).strftime('%d/%m/%y %H:%M')
      end
    end

    register_column(header: 'StdOut Path', verbose: true) { |j| j.stdout_path }
    register_column(header: 'StdErr Path', verbose: true) { |j| j.stderr_path }
    register_column(header: 'Results Dir', verbose: true) { |j| j.results_dir }

    def self.build_output(**opts)
      if opts.delete(:json)
        JSONRenderer.new(true, opts[:interactive])
      else
        super(row_color: :cyan, header_color: :bold, **opts)
      end
    end
  end
end

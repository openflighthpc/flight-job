# frozen_string_literal: true
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

require_relative 'flight_job/configuration'
require_relative 'flight'

module FlightJobMigration
  class MigrationError < FlightJob::InternalError; end

  module Jobs
    autoload 'MigrateV1', File.expand_path('flight_job_migration/jobs/v1.rb', __dir__)
    autoload 'MigrateV2', File.expand_path('flight_job_migration/jobs/v2.rb', __dir__)

    def self.migrate(dir)
      migrations = [
        Jobs::MigrateV1.new(dir),
        Jobs::MigrateV2.new(dir),
      ]
      migrations.all? do |migration|
        if migratation.applicable?
          migratation.migrate
        else
          false
        end
      end
    end
  end

  def self.migrate
    Jobs::MigrateV1.load_all.select(&:applicable?).each(&:migrate)
    Jobs::MigrateV2.load_all.select(&:applicable?).each(&:migrate)
  end
end

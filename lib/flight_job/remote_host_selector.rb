#==============================================================================
# Copyright (C) 2022-present Alces Flight Ltd.
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
#===============================================================================

require 'etc'
require 'pathname'
require 'securerandom'

module FlightJob
  class RemoteHostSelector
    def initialize(hosts)
      @hosts = hosts
    end

    def call
      # Each Flight Job process is short-lived and per-user. Implementing a
      # round-robin over the hosts would require some shared storage that each
      # process can read/write to.
      #
      # That seems like a lot of work for little gain.  Instead selecting a
      # random host should be sufficient.
      random_host
    end

    private

    def random_host
      @hosts.shuffle.first
    end
  end
end

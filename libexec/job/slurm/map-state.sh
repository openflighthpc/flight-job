#!/bin/bash
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

declare -A STATE_MAP=(
  ["BF"]="FAILED"
  ["BOOT_FAIL"]="FAILED"
  ["CA"]="CANCELLED"
  ["CANCELLED"]="CANCELLED"
  ["CD"]="COMPLETED"
  ["COMPLETED"]="COMPLETED"
  ["CF"]="RUNNING"
  ["CONFIGURING"]="RUNNING"
  ["CG"]="RUNNING"
  ["COMPLETING"]="RUNNING"
  ["DL"]="FAILED"
  ["DEADLINE"]="FAILED"
  ["F"]="FAILED"
  ["FAILED"]="FAILED"
  ["NF"]="FAILED"
  ["NODE_FAIL"]="FAILED"
  ["OOM"]="FAILED"
  ["OUT_OF_MEMORY"]="FAILED"
  ["PD"]="PENDING"
  ["PENDING"]="PENDING"
  ["PR"]="FAILED"
  ["PREEMPTED"]="FAILED"
  ["R"]="RUNNING"
  ["RUNNING"]="RUNNING"
  ["RD"]="PENDING"
  ["RESV_DEL_HOLD"]="PENDING"
  ["RF"]="PENDING"
  ["REQUEUE_FED"]="PENDING"
  ["RH"]="PENDING"
  ["REQUEUE_HOLD"]="PENDING"
  ["RQ"]="PENDING"
  ["REQUEUED"]="PENDING"
  ["RS"]="RUNNING"
  ["RESIZING"]="RUNNING"
  ["RV"]="FAILED" # Currently jobs cannot be tracked if they change cluster
  ["REVOKED"]="FAILED" # as above
  ["SI"]="RUNNING"
  ["SIGNALING"]="RUNNING"
  ["SE"]="PENDING"
  ["SPECIAL_EXIT"]="PENDING"
  ["SO"]="RUNNING"
  ["STAGE_OUT"]="RUNNING"
  ["ST"]="RUNNING" # This is a bit of a misnomer, consider defining a new state
  ["STOPPED"]="RUNNING" # as above
  ["S"]="RUNNING" # as above
  ["SUSPENDED"]="RUNNING" # as above
  ["TO"]="FAILED"
  ["TIMEOUT"]="FAILED"
)

function map_state {
  if [ -n "${STATE_MAP["$1"]}" ]; then
    echo "${STATE_MAP["$1"]}"
  else
    echo "UNKNOWN"
  fi
}

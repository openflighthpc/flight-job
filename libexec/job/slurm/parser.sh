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

# ==============================================================================
# State Mapping and helper functions
# ==============================================================================

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

function _parse_time {
  if [[ "$1" != "Unknown" ]]; then
    printf "$1"
  fi
}

function _parse_start_time {
  if echo "RUNNING COMPLETED FAILED CANCELLED" | grep "$2" >/dev/null; then
    _parse_time "$1"
  fi
}

function _parse_end_time {
  if echo "COMPLETED FAILED CANCELLED" | grep "$2" >/dev/null; then
    _parse_time "$1"
  fi
}

function _parse_estimated_start_time {
  if [ "PENDING" == "$2" ]; then
    _parse_time "$1"
  fi
}

function _parse_estimated_end_time {
  if echo "RUNNING PENDING" | grep "$2" >/dev/null; then
    _parse_time "$1"
  fi
}

function _parse_state {
  if [ -n "${STATE_MAP["$1"]}" ]; then
    printf "${STATE_MAP["$1"]}"
  else
    printf "UNKNOWN"
  fi
}

# ==============================================================================
# scontrol parsers
#
# NOTE:
# * Unless otherwise stated, these parsers are designed for an individual job/task
# * scontrol needs to be called with the --oneline flag
# ==============================================================================

# This function works on all scontrol outputs
function parse_scontrol_job_type {
  local control=$(echo "$1" | tr ' ' '\n')
  if echo "$control" | grep "ArrayJobId" >/dev/null; then
    printf "ARRAY"
  else
    printf "SINGLETON"
  fi
}

# This function works on all scontrol outputs
function parse_scontrol_scheduler_id {
  local control=$(echo "$1" | head -n 1 | tr ' ' '\n')
  if [ "$(parse_scontrol_job_type "$1")" == "ARRAY" ]; then
    echo "$control" | grep '^ArrayJobId=' | cut -d= -f2
  else
    echo "$control" | grep '^JobId=' | cut -d= -f2
  fi
}

function parse_scontrol_task_index {
  local control=$(echo "$1" | head -n 1 | tr ' ' '\n')
  echo "$control" | grep '^ArrayTaskId=' | cut -d= -f2
}

function parse_scontrol_state {
  local scheduler_state=$(parse_scontrol_scheduler_state "$1")
  _parse_state "$scheduler_state"
}

function parse_scontrol_scheduler_state {
  local control=$(echo "$1" | head -n 1 | tr ' ' '\n')
  echo "$control" | grep '^JobState=' | cut -d= -f2
}

function parse_scontrol_reason {
  local control=$(echo "$1" | head -n 1 | tr ' ' '\n')
  local reason=$(echo "$control" | grep '^Reason='   | cut -d= -f2)
  if [[ "$reason" != "None" ]]; then
    printf "$reason"
  fi
}

function parse_scontrol_stdout {
  local control=$(echo "$1" | head -n 1 | tr ' ' '\n')
  echo "$control" | grep '^StdOut=' | cut -d= -f2
}

function parse_scontrol_stderr {
  local control=$(echo "$1" | head -n 1 | tr ' ' '\n')
  echo "$control" | grep '^StdErr=' | cut -d= -f2
}

function parse_scontrol_start_time {
  local state="$2"
  local control=$(echo "$1" | head -n 1 | tr ' ' '\n')

  # Check if CANCELLED jobs actually started
  if [ "$state" == "CANCELLED" ]; then
    if [[ "$(echo "$control" | grep "^NodeList=" | cut -d= -f2)" == "(null)" ]]; then
      return 0
    fi
  fi

  local time=$(echo "$control" | grep '^StartTime=' | cut -d= -f2)
  _parse_start_time "$time" "$state"
}

function parse_scontrol_end_time {
  local state="$2"
  local control=$(echo "$1" | head -n 1 | tr ' ' '\n')
  local time=$(echo "$control" | grep '^EndTime=' | cut -d= -f2)
  _parse_end_time "$time" "$state"
}

function parse_scontrol_estimated_start_time {
  local state="$2"
  local control=$(echo "$1" | head -n 1 | tr ' ' '\n')
  local time=$(echo "$control" | grep '^StartTime=' | cut -d= -f2)
  _parse_estimated_start_time "$time" "$state"
}

function parse_scontrol_estimated_end_time {
  local state="$2"
  local control=$(echo "$1" | head -n 1 | tr ' ' '\n')
  local time=$(echo "$control" | grep '^EndTime=' | cut -d= -f2)
  _parse_estimated_end_time "$time" "$state"
}

# ==============================================================================
# sacct parsers
#
# NOTE: All sacct parsers are designed for a single row with:
#       --format State,Reason,START,END,AllocTRES,JobID
# ==============================================================================

function parse_sacct_state {
  local scheduler_state=$(parse_sacct_scheduler_state "$1")
  _parse_state "$scheduler_state"
}

function parse_sacct_scheduler_state {
  echo "$1" | cut -d'|' -f1 | cut -d' ' -f1
}

function parse_sacct_reason {
  echo "$1" | cut -d'|' -f2
}

function parse_sacct_start_time {
  local state="$2"

  # Check if CANCELLED jobs actually started
  if [ "$state" == "CANCELLED" ]; then
    # Skip setting the start_time when there are no allocated TRESS
    if [ -z "$(echo "$acct" | cut -d'|' -f5)" ]; then
      return 0
    fi
  fi

  local time=$(echo "$1" | cut -d'|' -f3)
  _parse_start_time "$time" "$state"
}

function parse_sacct_end_time {
  local state="$2"
  local time=$(echo "$1" | cut -d'|' -f4)
  _parse_end_time "$time" "$state"
}

function parse_sacct_estimated_start_time {
  local state="$2"
  local time=$(echo "$1" | cut -d'|' -f3)
  _parse_estimated_start_time "$time" "$state"
}

function parse_sacct_estimated_end_time {
  local state="$2"
  local time=$(echo "$1" | cut -d'|' -f4)
  _parse_estimated_end_time "$time" "$state"
}

function parse_sacct_task_index {
  local state="$2"
  echo "$1" | cut -d'|' -f6 | sed 's/^.*_//g'
}

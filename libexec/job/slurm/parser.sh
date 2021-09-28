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

_parse_time() {
  if [[ "$1" != "Unknown" ]]; then
    printf "$1"
  fi
}

_parse_start_time() {
  if echo "RUNNING COMPLETED FAILED CANCELLED" | grep -q "$2"; then
    _parse_time "$1"
  fi
}

_parse_end_time() {
  if echo "COMPLETED FAILED CANCELLED" | grep -q "$2"; then
    _parse_time "$1"
  fi
}

_parse_estimated_start_time() {
  if [ "PENDING" == "$2" ]; then
    _parse_time "$1"
  fi
}

_parse_estimated_end_time() {
  if echo "RUNNING PENDING" | grep -q "$2"; then
    _parse_time "$1"
  fi
}

_parse_state() {
  if [ -n "${STATE_MAP["$1"]}" ]; then
    printf "${STATE_MAP["$1"]}"
  else
    printf "UNKNOWN"
  fi
}

# ==============================================================================
# scontrol parsers
#
# These parsers parse a variant of `scontrol` output.  The variant can be
# achieved by running `scontrol` as:
#
# ```
# scontrol show job <ID> --oneline | head -n 1 | tr ' ' '\n'
# ```
# ==============================================================================

# Extracts the value for the given key and prints to stdout.
#
# The parse input is read from $1 or stdin.
parse_scontrol() {
    local key_name
    key_name="$1"
    shift
    if (( $# == 0 )) ; then
        cat       | grep "^${key_name}=" | cut -d= -f2
    else
        echo "$1" | grep "^${key_name}=" | cut -d= -f2
    fi
}

# Returns 0 if the scontrol input contains the given key.  The value of the
# key is ignored, so a blank value counts as the key being present.
#
# The parse input is read from $1 or stdin.
_scontrol_contains_key() {
    local key_name
    key_name="$1"
    shift
    if (( $# == 0 )) ; then
        cat       | grep -q "^${key_name}="
    else
        echo "$1" | grep -q "^${key_name}="
    fi
}

# This function works on all scontrol outputs
parse_scontrol_job_type() {
    if _scontrol_contains_key "ArrayJobId" ; then
        printf "ARRAY"
    else
        printf "SINGLETON"
    fi
}

# This function works on all scontrol outputs
parse_scontrol_scheduler_id() {
    local input
    input=$(cat)
    if [ "$(parse_scontrol_job_type <<< "${input}")" == "ARRAY" ] ; then
        parse_scontrol "ArrayJobId" <<< "${input}"
    else
        parse_scontrol "JobId" <<< "${input}"
    fi
}

parse_scontrol_job_id() {
    parse_scontrol JobId
}

parse_scontrol_task_index() {
    parse_scontrol ArrayTaskId
}

parse_scontrol_state() {
    local scheduler_state
    if (( $# == 0 )) ; then
        scheduler_state=$(parse_scontrol_scheduler_state)
    else
        scheduler_state=$(parse_scontrol_scheduler_state <<< "$1")
    fi
    _parse_state "$scheduler_state"
}

parse_scontrol_scheduler_state() {
    parse_scontrol JobState
}

parse_scontrol_reason() {
    local reason
    reason="$(parse_scontrol Reason)"
    if [[ "$reason" != "None" ]]; then
        printf "$reason"
    fi
}

parse_scontrol_stdout() {
    parse_scontrol StdOut
}

parse_scontrol_stderr() {
    parse_scontrol StdErr
}

parse_scontrol_start_time() {
    local state control time
    state="$2"
    control="$1"

    # Check if CANCELLED jobs actually started
    if [ "$state" == "CANCELLED" ]; then
        if [[ "$(parse_scontrol NodeList "$control")" == "(null)" ]] ; then
            return 0
        fi
    fi

    time=$(parse_scontrol StartTime "$control")
    _parse_start_time "$time" "$state"
}

parse_scontrol_end_time() {
    local state time
    state="$2"
    time=$(parse_scontrol EndTime "$1")
    _parse_end_time "$time" "$state"
}

parse_scontrol_estimated_start_time() {
    local state time
    state="$2"
    time=$(parse_scontrol StartTime "$1")
    _parse_estimated_start_time "$time" "$state"
}

parse_scontrol_estimated_end_time() {
    local state time
    state="$2"
    time=$(parse_scontrol EndTime "$1")
    _parse_estimated_end_time "$time" "$state"
}

# ==============================================================================
# sacct parsers
#
# NOTE: All sacct parsers are designed for a single row with:
#       --format State,Reason,START,END,AllocTRES,JobID,JobIDRaw
# ==============================================================================

parse_sacct_field() {
    local field
    field="$1"
    shift
    if (( $# == 0 )) ; then
        cat       | cut -d'|' -f${field}
    else
        echo "$1" | cut -d'|' -f${field}
    fi
}

parse_sacct_state() {
    local scheduler_state
    scheduler_state=$(parse_sacct_scheduler_state "$1")
    _parse_state "$scheduler_state"
}

parse_sacct_scheduler_state() {
    parse_sacct_field 1 "$1" | cut -d' ' -f1
}

parse_sacct_reason() {
    parse_sacct_field 2 "$1"
}

parse_sacct_start_time() {
    local state time
    state="$2"

    # Check if CANCELLED jobs actually started
    if [ "$state" == "CANCELLED" ]; then
        # Skip setting the start_time when there are no allocated TRESS
        if [ -z "$(echo "$1" | cut -d'|' -f5)" ]; then
            return 0
        fi
    fi

    time=$(parse_sacct_field 3 "$1")
    _parse_start_time "$time" "$state"
}

parse_sacct_end_time() {
    local state time
    state="$2"
    time=$(parse_sacct_field 4 "$1")
    _parse_end_time "$time" "$state"
}

parse_sacct_estimated_start_time() {
    local state time
    state="$2"
    time=$(parse_sacct_field 3 "$1")
    _parse_estimated_start_time "$time" "$state"
}

parse_sacct_estimated_end_time() {
    local state time
    state="$2"
    time=$(parse_sacct_field 4 "$1")
    _parse_estimated_end_time "$time" "$state"
}

parse_sacct_task_index() {
    parse_sacct_field 6 "$1" | sed 's/^.*_//g'
}

parse_sacct_job_id_raw() {
    parse_sacct_field 7 "$1"
}

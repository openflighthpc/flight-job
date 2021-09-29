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
parse_field() {
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

parse_job_type() {
    if _scontrol_contains_key "ArrayJobId" ; then
        printf "ARRAY"
    else
        printf "SINGLETON"
    fi
}

parse_scheduler_id() {
    local input
    input=$(cat)
    if [ "$(parse_job_type <<< "${input}")" == "ARRAY" ] ; then
        parse_field "ArrayJobId" <<< "${input}"
    else
        parse_field "JobId" <<< "${input}"
    fi
}

# Return the JobID.
#
# For non ARRAY_TASKs the meaning of JobID is clear.
#
# ARRAY_TASKs have essentially two IDs: `<ARRAY_JOB_ID>_<TASK_INDEX>` and its
# own JobID.  This function returns the latter of those.
parse_job_id() {
    parse_field JobId
}

parse_task_index() {
    parse_field ArrayTaskId
}

parse_state() {
    _parse_state "$(parse_scheduler_state)"
}

parse_scheduler_state() {
    parse_field JobState
}

parse_reason() {
    local reason
    reason="$(parse_field Reason)"
    if [[ "$reason" != "None" ]]; then
        printf "$reason"
    fi
}

parse_stdout() {
    parse_field StdOut
}

parse_stderr() {
    parse_field StdErr
}

parse_start_time() {
    local state control time
    state="$1"
    control="$(cat)"

    # Check if CANCELLED jobs actually started
    if [ "$state" == "CANCELLED" ]; then
        if [[ "$(parse_field NodeList "$control")" == "(null)" ]] ; then
            return 0
        fi
    fi

    time=$(parse_field StartTime "$control")
    _parse_start_time "$time" "$state"
}

parse_end_time() {
    local state time
    state="$1"
    time=$(parse_field EndTime)
    _parse_end_time "$time" "$state"
}

parse_estimated_start_time() {
    local state time
    state="$1"
    time=$(parse_field StartTime)
    _parse_estimated_start_time "$time" "$state"
}

parse_estimated_end_time() {
    local state time
    state="$1"
    time=$(parse_field EndTime)
    _parse_estimated_end_time "$time" "$state"
}

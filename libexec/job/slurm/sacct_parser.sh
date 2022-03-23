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
# sacct parsers
#
# All sacct parsers are designed for a single row with:
#    --format State,Reason,START,END,AllocTRES,JobID,JobIDRaw,JobName,WorkDir
# ==============================================================================

parse_field() {
    local field
    field="$1"
    case "${field}" in
        State)
            field="1"
            ;;
        Reason)
            field="2"
            ;;
        START)
            field="3"
            ;;
        END)
            field="4"
            ;;
        AllocTRES)
            field="5"
            ;;
        JobID)
            field="6"
            ;;
        JobIDRaw)
            field="7"
            ;;
        JobName)
            field="8"
            ;;
        WorkDir)
            field="9"
            ;;
        *)
    esac
    cat | cut -d'|' -f${field}
}

parse_scheduler_state() {
    parse_field 1 | cut -d' ' -f1
}

parse_reason() {
    local reason
    reason="$(parse_field 2)"
    if [[ "$reason" != "None" ]]; then
        printf "$reason"
    fi
}

parse_start_time() {
    local state time input
    state="$1"
    input=$(cat)

    # Check if CANCELLED jobs actually started
    if [ "$state" == "CANCELLED" ]; then
        # Skip setting the start_time when there are no allocated TRESS
        if [ -z "$(parse_field 5 <<< "$input")" ]; then
            return 0
        fi
    fi

    time=$(parse_field 3 <<< "$input")
    start_time_if_valid_state "$time" "$state"
}

parse_end_time() {
    local state time
    state="$1"
    time=$(parse_field 4)
    end_time_if_valid_state "$time" "$state"
}

parse_estimated_start_time() {
    local state time
    state="$1"
    time=$(parse_field 3)
    estimated_start_time_if_valid_state "$time" "$state"
}

parse_estimated_end_time() {
    local state time
    state="$1"
    time=$(parse_field 4)
    estimated_end_time_if_valid_state "$time" "$state"
}

parse_task_index() {
    parse_field 6 | sed 's/^.*_//g'
}

# Return the JobID.
#
# For non ARRAY_TASKs the meaning of JobID is clear.
#
# ARRAY_TASKs have essentially two IDs: `<ARRAY_JOB_ID>_<TASK_INDEX>` and its
# own JobID.  This function returns the latter of those.
parse_job_id() {
    parse_field 7
}

parse_job_type() {
    local input job_id raw_job_id
    input=$(cat)
    job_id=$(parse_field "JobID" <<< "${input}")
    raw_job_id=$(parse_field "JobIDRaw" <<< "${input}")
    if [ "${job_id}" == "${raw_job_id}" ] ; then
        printf "SINGLETON"
    else
        printf "ARRAY"
    fi
}

parse_stdout() {
    :
}

parse_stderr() {
    :
}

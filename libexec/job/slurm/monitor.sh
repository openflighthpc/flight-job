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

#-------------------------------------------------------------------------------
# WARNING do not modify this file.
#
# If this file is not suitable for your cluster environment, please follow the
# instructions at
# https://github.com/openflighthpc/flight-job/blob/master/docs/scheduler-integration.md
# to create a custom scheduler integration.
#-------------------------------------------------------------------------------

set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "${DIR}/functions.sh"
source "${DIR}/parser.sh"

run_scontrol() {
    # scontrol show job "${1}" --oneline | head -n1 | tr ' ' '\n'
    scontrol show job "${1}" --oneline 2>&1
}

parse_scontrol_output() {
    assert_array_var PARSE_RESULT
    local parse_input state

    parse_input="$(cat)"
    PARSE_RESULT[state]=$(parse_scontrol_state <<< "${parse_input}")
    state="${PARSE_RESULT[state]}"
    PARSE_RESULT[scheduler_state]=$(parse_scontrol_scheduler_state <<< "${parse_input}")
    PARSE_RESULT[reason]=$(parse_scontrol_reason <<< "${parse_input}")
    PARSE_RESULT[start_time]=$(parse_scontrol_start_time "${parse_input}" "${state}")
    PARSE_RESULT[end_time]=$(parse_scontrol_end_time "${parse_input}" "${state}")
    PARSE_RESULT[estimated_start_time]=$(parse_scontrol_estimated_start_time "${parse_input}" "$state")
    PARSE_RESULT[estimated_end_time]=$(parse_scontrol_estimated_end_time "${parse_input}" "$state")
    PARSE_RESULT[stdout_path]=$(parse_scontrol_stdout <<< "${parse_input}")
    PARSE_RESULT[stderr_path]=$(parse_scontrol_stderr <<< "${parse_input}")
}

run_sacct() {
  sacct --noheader --parsable --jobs "$1" --format State,Reason,START,END,AllocTRES
}

parse_sacct_output() {
    assert_array_var PARSE_RESULT
    local parse_input state

    parse_input="$(cat)"
    PARSE_RESULT[state]=$(parse_sacct_state  "${parse_input}")
    state="${PARSE_RESULT[state]}"
    PARSE_RESULT[scheduler_state]=$(parse_sacct_scheduler_state "${parse_input}")
    PARSE_RESULT[reason]=$(parse_sacct_reason "${parse_input}")
    PARSE_RESULT[start_time]=$(parse_sacct_start_time "${parse_input}" "$state")
    PARSE_RESULT[end_time]=$(parse_sacct_end_time   "${parse_input}" "$state")
    PARSE_RESULT[estimated_start_time]=$(parse_sacct_estimated_start_time "${parse_input}" "$state")
    PARSE_RESULT[estimated_end_time]=$(parse_sacct_estimated_end_time   "${parse_input}" "$state")
}


generate_template() {
    local template

    # Specify the template for the JSON response
    # NOTE: scontrol does not distinguish between actual/estimated times. Instead
    #       flight-job will set the times according to the state
    read -r -d '' template <<'TEMPLATE' || true
{
  version: 1,
  state: (
    if $state == "" then "UNKNOWN" else $state end
  ),
  scheduler_state: ($scheduler_state),
  reason: (
    if $reason == "" then null else $reason end
  ),
  stdout_path: (
    if $stdout_path == "" then null else $stdout_path end
  ),
  stderr_path: (
    if $stderr_path == "" then null else $stderr_path end
  ),
  start_time: (
    if $start_time == ""  then null else $start_time end
  ),
  end_time: (
    if $end_time == "" then null else $end_time end
  ),
  estimated_start_time: (
    if $estimated_start_time == "" then null else $estimated_start_time end
  ),
  estimated_end_time: (
    if $estimated_end_time == "" then null else $estimated_end_time end
  )
}
TEMPLATE

    echo '{}' | jq  --arg state "${PARSE_RESULT[state]}" \
        --arg scheduler_state "${PARSE_RESULT[scheduler_state]}" \
        --arg reason "${PARSE_RESULT[reason]}" \
        --arg estimated_start_time "${PARSE_RESULT[estimated_start_time]}" \
        --arg estimated_end_time "${PARSE_RESULT[estimated_end_time]}" \
        --arg start_time "${PARSE_RESULT[start_time]}" \
        --arg end_time "${PARSE_RESULT[end_time]}" \
        --arg stdout_path "${PARSE_RESULT[stdout_path]}" \
        --arg stderr_path "${PARSE_RESULT[stderr_path]}" \
        "$template"
}

main() {
    declare -A PARSE_RESULT
    local exit_status
    local output

    check_progs jq scontrol sacct

    # Fetch the state of the job
    output=$(run_scontrol "$1" | tee >(log_command "scontrol" 1>&2))
    exit_status=$?

    if [[ $exit_status -eq 0 ]] ; then
        output="$(echo "$output" | head -n 1 | tr ' ' '\n')"
        parse_scontrol_output <<< "${output}"
    elif [[ "${output}" == "slurm_load_jobs error: Invalid job id specified" ]] ; then
        output=$(run_sacct "$1" | tee >(log_command "sacct" 1>&2))
        exit_status=$?
        output=$(echo "$output" | head -n1)
        if [[ $exit_status -eq 0 ]] && [ -z "$output" ]; then
            PARSE_RESULT[state]="UNKNOWN"
        elif [[ $exit_status -eq 0 ]]; then
            parse_sacct_output <<< "${output}"
        else
            exit $exit_status
        fi
    else
        exit $exit_status
    fi

    declare -p PARSE_RESULT >&2

    generate_template | report_metadata
}

main "$@"

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

generate_task_json() {
    assert_assoc_array_var TASK

    read -r -d '' task_template <<'TEMPLATE' || true
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

    echo '{}' | jq  \
      --arg state "${TASK[state]}" \
      --arg scheduler_state "${TASK[scheduler_state]}" \
      --arg reason "${TASK[reason]}" \
      --arg stdout_path "${TASK[stdout_path]}" \
      --arg stderr_path "${TASK[stderr_path]}" \
      --arg estimated_start_time "${TASK[estimated_start_time]}" \
      --arg estimated_end_time "${TASK[estimated_end_time]}" \
      --arg start_time "${TASK[start_time]}" \
      --arg end_time "${TASK[end_time]}" \
      "$task_template"
}

generate_template() {
    assert_assoc_array_var ARRAY_JOB
    local template
    read -r -d '' template <<'TEMPLATE' || true
{
  version: 1,
  lazy: (if $lazy == "true" then true else false end),
  tasks: ($tasks)
}
TEMPLATE

    echo '{}' | jq  \
      --arg lazy "${ARRAY_JOB[lazy]}" \
      --argjson tasks "${ARRAY_JOB[tasks]}" \
      "$template"
}

# There are multiple definitions of run_scontrol in the Slurm integration.
#
# XXX Find a mechanism to remove the difference and extract to a common
# location (scontrol_parser.sh).
run_scontrol() {
    scontrol show job "${1}" --oneline 2>&1
}

run_sacct() {
  sacct --noheader --parsable --jobs "$1" --format State,Reason,START,END,AllocTRES,JobID,JobIDRaw
}

parse_scontrol_output() {
    assert_assoc_array_var ARRAY_JOB
    declare -A TASK
    local tasks

    tasks='{}'

    while read -r line; do
        unset TASK
        declare -A TASK
        line=$(echo "$line" | tr ' ' '\n')
        index=$(parse_task_index <<< "${line}")
        if echo "${index}" | grep -P '^\d+$' >/dev/null; then
            parse_task <<< "${line}"
            # declare -p TASK >&2
            tasks="$(json_object_insert "$tasks" "$index" "$(generate_task_json)")"
        fi

        if [ "$(parse_job_id <<< "${line}")" == "${JOB_ID}" ] ; then
            ARRAY_JOB[state]=$(parse_state <<< "${line}")
        fi
    done

    ARRAY_JOB[tasks]="$tasks"
}

parse_sacct_output() {
    assert_assoc_array_var ARRAY_JOB
    declare -A TASK
    local tasks

    tasks="${ARRAY_JOB[tasks]}"
    if [ -z "$tasks" ]; then
      tasks="{}"
    fi

    while IFS= read -r line; do
        index=$(parse_task_index <<< "$line")
        existing_task=$(printf "$tasks" | jq ".[\"$index\"]")
        numeric_id=$(echo "${index}" | grep -P '^\d+$')

        if [ "$existing_task" == "null" ] && [ -n "$numeric_id" ]; then
          unset TASK
          declare -A TASK
          parse_task <<< "${line}"
          # declare -p TASK >&2
          tasks="$(json_object_insert "$tasks" "$index" "$(generate_task_json)")"
        fi

        if [ "$(parse_job_id <<< "$line")" == "${JOB_ID}" ] ; then
            ARRAY_JOB[state]=$(parse_state <<< "$line")
        fi
    done

    ARRAY_JOB[tasks]="${tasks}"
}

main() {
    JOB_ID="$1"
    declare -A ARRAY_JOB
    local exit_status output

    assert_progs jq scontrol sacct

    ARRAY_JOB[lazy]="false"
    ARRAY_JOB[state]="UNKNOWN"

    # First attempt to get the data from scontrol
    output=$(run_scontrol "${JOB_ID}" | tee >(log_command "scontrol" 1>&2))
    scontrol_exit_status=$?
    if [[ $scontrol_exit_status -eq 0 ]] ; then
        source_parsers "scontrol"
        parse_scontrol_output <<< "$output"
    fi

    # Second, attempt to load additional data from sacct
    # NOTE: The earliest tasks may move here before the last finishes
    # XXX Replace with -X / --allocations
    output=$(run_sacct "$JOB_ID" | tee >(log_command "sacct" 1>&2))
    output=$(echo "$output" | awk 'FNR%2')
    sacct_exit_status=$?
    if [[ $sacct_exit_status -eq 0 ]] && [ -z "$output" ]; then
        echo "No Tasks Found!" >&2
    elif [[ $sacct_exit_status -eq 0 ]]; then
        source_parsers "sacct"
        parse_sacct_output <<< "${output}"
    fi

    # Exit if both commands failed
    if [ $scontrol_exit_status -ne 0 ] && [ $sacct_exit_status -ne 0 ]; then
        exit $sacct_exit_status
    fi

    if echo "RUNNING" "PENDING" | grep -q "${ARRAY_JOB[state]}" ; then
        ARRAY_JOB[lazy]="true"
    else
        ARRAY_JOB[lazy]="false"
    fi

    generate_template | report_metadata
}

main "$@"

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

# There are multiple definitions of run_scontrol in the Slurm integration.
#
# XXX Extract to a common location (scontrol_parser.sh?).
run_scontrol() {
    scontrol show job "${1}" --oneline 2>&1
}

# There are multiple definitions of run_sacct in the Slurm integration.
#
# XXX Remove the difference and extract to a common location
# (scontrol_parser.sh?).
run_sacct() {
  sacct --noheader --parsable --jobs "$1" \
      --format State,Reason,START,END,AllocTRES,JobId,JobIDRaw,JobName,WorkDir
}

parse_job() {
    assert_assoc_array_var JOB
    local working_dir job_name parse_input scheduler_id

    scheduler_id="$1"
    parse_input="$(cat)"
    working_dir=$(parse_field WorkDir <<< "${parse_input}")
    job_name=$(parse_field JobName <<< "${parse_input}")

    JOB[job_type]=$(parse_job_type <<< "${parse_input}")
    JOB[results_dir]="${working_dir}/${job_name}-outputs/${scheduler_id}"
}

# Print to stdout the JSON template to be returned to flight job.
generate_template() {
    assert_assoc_array_var JOB
    local template

    read -r -d '' template <<'TEMPLATE' || true
{
  version: 2,
  job_type: ($job_type),
  results_dir: ($results_dir)
}
TEMPLATE

  echo '{}' | jq  \
    --arg results_dir "${JOB[results_dir]}"  \
    --arg job_type    "${JOB[job_type]}"     \
    "$template"
}

main() {
    JOB_ID="$1"
    declare -A JOB
    local exit_status output 

    assert_progs jq scontrol

    output=$(run_scontrol "${JOB_ID}" | tee >(log_command "scontrol" 1>&2))
    exit_status=$?

    if [[ $exit_status -eq 0 ]]; then
        output="$(echo "$output" | head -n 1 | tr ' ' '\n')"
        source_parsers "scontrol"
        parse_job "${JOB_ID}" <<< "${output}"
    elif [[ "${output}" == "slurm_load_jobs error: Invalid job id specified" ]] ; then
        output=$(run_sacct "${JOB_ID}" | tee >(log_command "sacct" 1>&2))
        exit_status=$?
        output=$(echo "$output" | head -n1)
        if [[ $exit_status -eq 0 ]]; then
            source_parsers "sacct"
            parse_job "${JOB_ID}" <<< "${output}"
        else
            exit $exit_status
        fi
    else
        exit $exit_status
    fi

    # declare -p JOB >&2

    generate_template | report_metadata
    exit 0
}

main "$@"

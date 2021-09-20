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
# WARNING - README
#
# This is an internally managed file, any changes maybe lost on the next update!
# Please make any installation specific changes within the provided 'sbatch.sh'
# script or clone the entire 'slurm' directory.
#-------------------------------------------------------------------------------

set -o pipefail
# set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "${DIR}/functions.sh"
source "${DIR}/parser.sh"

submit_job() {
    $DIR/sbatch-wrapper.sh "$1"
}

parse_submission_id() {
    assert_array_var PARSE_RESULT
    PARSE_RESULT[submission_id]=$( cut -d' ' -f4)
}

run_scontrol() {
    scontrol show job "${1}" --oneline | head -n1 | tr ' ' '\n'
}

parse_scontrol_output() {
    assert_array_var PARSE_RESULT
    local working
    local name
    local scontrol_output
    local submission_id

    submission_id="${PARSE_RESULT[submission_id]}"
    scontrol_output="$(cat)"
    PARSE_RESULT[job_type]=$(parse_scontrol_job_type <<< "${scontrol_output}")
    PARSE_RESULT[scheduler_id]=$(parse_scontrol_scheduler_id <<< "${scontrol_output}")
    PARSE_RESULT[results_dir]=$(parse_results_dir "${submission_id}" <<< "${scontrol_output}")
}

parse_results_dir() {
    local working name scontrol_output submission_id
    submission_id="$1"

    scontrol_output="$(cat)"
    working=$(parse_scontrol WorkDir <<< "${scontrol_output}")
    name=$(parse_scontrol JobName <<< "${scontrol_output}")
    echo "${working}/${name}-outputs/${submission_id}"
}

# Print to stdout the JSON template to be returned to flight job.
generate_template() {
    local template

    read -r -d '' template <<'TEMPLATE' || true
{
  version: 1,
  job_type: ($job_type),
  id: ($id),
  results_dir: ($results_dir)
}
TEMPLATE

  echo '{}' | jq  \
    --arg id          "${PARSE_RESULT[scheduler_id]}" \
    --arg results_dir "${PARSE_RESULT[results_dir]}"  \
    --arg job_type    "${PARSE_RESULT[job_type]}"     \
    "$template"
}

main() {
    declare -A PARSE_RESULT
    local exit_status
    local output

    check_progs jq scontrol sbatch

    output="$(submit_job "$1" | tee >(log_command "sbatch wrapper" 1>&2))"
    exit_status=$?
    if [[ $exit_status -ne 0 ]]; then
        exit $exit_status
    fi
    parse_submission_id <<< "${output}"

    output=$(run_scontrol "${PARSE_RESULT[submission_id]}" | tee >(log_command "scontrol" 1>&2))
    exit_status=$?
    if [[ $exit_status -ne 0 ]]; then
        exit $exit_status
    fi

    parse_scontrol_output <<< "${output}"
    declare -A | grep PARSE_RESULT >&2

    generate_template | report_metadata
}

main "$@"

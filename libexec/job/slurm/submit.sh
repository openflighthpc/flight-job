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

submit_job() {
    $DIR/sbatch-wrapper.sh "$@"
}

# Parse the scheduler id from `sbatch` output and set into JOB associative
# array.
parse_scheduler_id() {
    assert_assoc_array_var JOB
    JOB[scheduler_id]=$( cut -d' ' -f4)
}

# Print to stdout the JSON template to be returned to flight job.
generate_template() {
    assert_assoc_array_var JOB
    local template

    read -r -d '' template <<'TEMPLATE' || true
{
  version: 1,
  id: ($id)
}
TEMPLATE

  echo '{}' | jq  \
    --arg id "${JOB[scheduler_id]}" \
    "$template"
}

main() {
    declare -A JOB
    local exit_status output

    assert_progs jq sbatch

    output="$(submit_job "$@" | tee >(log_command "sbatch wrapper" 1>&2))"
    exit_status=$?
    if [[ $exit_status -ne 0 ]]; then
        exit $exit_status
    fi
    parse_scheduler_id <<< "${output}"
    declare -p JOB >&2

    generate_template | report_metadata
    exit 0
}

main "$@"

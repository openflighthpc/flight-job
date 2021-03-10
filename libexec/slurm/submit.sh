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

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Ensure jq is on the path
set -e
which "jq"

# Specify the template for the JSON response
read -r -d '' template <<'TEMPLATE' || true
{
  id: ($id),
  stdout: ($stdout),
  stderr: ($stderr)
}
TEMPLATE

# Submit the job to the scheduler
output=$($DIR/sbatch.sh "$1")
if [[ $? -ne 0 ]]; then
  exit $?
fi

# Determine the scheduler's ID
id=$(echo "$output" | cut -d' ' -f4)
if [[ $? -ne 0 ]]; then
  exit $?
fi

# Fetch the details about the job
control=$(scontrol show job "$id")
if [[ $? -ne 0 ]]; then
  exit $?
fi

# Extract the sdout/stderr paths
stdout=$(echo "$control" | grep -E "^\s*StdOut=" | sed "s/^\s*StdOut=//g")
stderr=$(echo "$control" | grep -E "^\s*StdErr=" | sed "s/^\s*StdErr=//g")

# Render and return the JSON payload
echo '{}' | jq --arg id "$id" --arg stdout "$stdout" --arg stderr "$stderr" "$template" | tr -d "\n"

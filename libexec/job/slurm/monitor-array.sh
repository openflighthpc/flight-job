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
# Please clone the entire 'slurm' directory in order to modify this file.
#-------------------------------------------------------------------------------

# Ensure jq is on the path
set -e
which "jq" >/dev/null
set +e

# Source the parser
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/parser.sh"

# Specify the template for the JSON response
# NOTE: scontrol does not distinguish between actual/estimated times. Instead
#       flight-job will set the times according to the state
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

# Define the tasks variables
lazy="false"
tasks=""

# Fetch the state of the job
raw_control=$(scontrol show job "$1" --oneline 2>&1)
exit_status="$?"
cat <<EOF >&2
scontrol:
$raw_control
EOF

if [[ "$exit_status" -eq 0 ]]; then
  while IFS= read -r line; do
    index=$(parse_scontrol_task_index "$line")
    if echo "$index" | grep '-' >/dev/null; then
      # Skipping the pseudo-task entry, setting the lazy create flag
      lazy="true"
    else
      # Generate and store the JSON for the task
      state=$(                parse_scontrol_state  "$line")
      scheduler_state=$(      parse_scontrol_scheduler_state "$line")
      reason=$(               parse_scontrol_reason "$line")
      start_time=$(           parse_scontrol_start_time "$line" "$state")
      end_time=$(             parse_scontrol_end_time   "$line" "$state")
      estimated_start_time=$( parse_scontrol_estimated_start_time "$line" "$state")
      estimated_end_time=$(   parse_scontrol_estimated_end_time   "$line" "$state")

      json=$( \
        echo '{}' | jq  \
          --arg state "$state" \
          --arg scheduler_state "$scheduler_state" \
          --arg reason "$reason" \
          --arg estimated_start_time "$estimated_start_time" \
          --arg estimated_end_time "$estimated_end_time" \
          --arg start_time "$start_time" \
          --arg end_time "$end_time" \
          "$task_template" \
      )
      tasks="$tasks, \"$index\" : $json"
    fi
  done <<< "$raw_control"
elif [[ "$raw_control" == "slurm_load_jobs error: Invalid job id specified" ]]; then
  # Fallback to sacct if scontrol does not recognise the ID
  raw_acct=$(sacct --noheader --parsable --jobs "$1" --format State,Reason,START,END,AllocTRES,JobID)
  exit_status="$?"
  cat <<EOF >&2

sacct:
$raw_acct
EOF

  # Remove every second line from output
  # NOTE: sacct output looks something like this:
  #
  # COMPLETED|None|2021-09-01T15:58:03|2021-09-01T15:58:03|billing=1,cpu=1,mem=1M,node=1|155_1|
  # COMPLETED||2021-09-01T15:58:03|2021-09-01T15:58:03|cpu=1,mem=1M,node=1|155_1.batch|
  acct=$(echo "$raw_acct" | awk 'FNR%2')

  if [[ "$exit_status" -eq 0 ]] && [ -z "$acct" ]; then
    # NOOP
    echo "No Tasks Found!" >&2

  elif [[ "$exit_status" -eq 0 ]]; then
    while IFS= read -r line; do
      state=$(                parse_sacct_state  "$line")
      scheduler_state=$(      parse_sacct_scheduler_state "$line")
      reason=$(               parse_sacct_reason "$line")
      start_time=$(           parse_sacct_start_time "$line" "$state")
      end_time=$(             parse_sacct_end_time   "$line" "$state")
      estimated_start_time=$( parse_sacct_estimated_start_time "$line" "$state")
      estimated_end_time=$(   parse_sacct_estimated_end_time   "$line" "$state")

      # Generate the index/json
      index=$(parse_sacct_task_index "$line")
      json=$( \
        echo '{}' | jq  \
          --arg state "$state" \
          --arg scheduler_state "$scheduler_state" \
          --arg reason "$reason" \
          --arg estimated_start_time "$estimated_start_time" \
          --arg estimated_end_time "$estimated_end_time" \
          --arg start_time "$start_time" \
          --arg end_time "$end_time" \
          "$task_template" \
      )

      # Store the task as a JSON fragment
      tasks="$tasks, \"$index\" : $json"
    done <<< "$acct"

  # Exit the monitor process if sacct fails to prevent the job being updated
  else
    echo "$sacct" >&3
    exit "$exit_status"
  fi
else
  # Exit the monitor process if scontrol fails to prevent the job being updated
  exit "$exit_status"
fi

# Reform tasks into valid JSON (remove leading comma/ add braces)
tasks=$(echo "$tasks" | sed 's/^,//g')
tasks="{ $tasks }"

# Render the response JSON
read -r -d '' template <<'TEMPLATE' || true
{
  version: 1,
  lazy: (if $lazy == "true" then true else false end),
  tasks: ($tasks)
}
TEMPLATE
echo '{}' | jq  \
  --arg lazy "$lazy" \
  --argjson tasks "$tasks" \
  "$template" | tr -d "\n"

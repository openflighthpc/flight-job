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

# Specify the template for the JSON response
read -r -d '' template <<'TEMPLATE' || true
{
  state: ($state),
  reason: ($reason),
  start_time: (if $start_time == "" then null else $start_time end),
  end_time: (if $end_time == "" then null else $end_time end)
}
TEMPLATE

# Fetch the state of the job
raw_control=$(scontrol show job "$1" --oneline 2>&1)
exit_status="$?"
control=$(echo "$raw_control" | head -n 1 | tr ' ' '\n')
cat <<EOF
scontrol:
$raw_control
EOF

if [[ "$exit_status" -eq 0 ]]; then
  state=$( echo "$control" | grep '^JobState=' | cut -d= -f2)
  reason=$(echo "$control" | grep '^Reason='   | cut -d= -f2)
  if [[ "$reason" == "None" ]]; then
    reason=""
  fi

  if [[ "$(echo "$control" | grep "^NodeList=" | cut -d= -f2)" -eq "(null)" ]]; then
    # Skip setting the start_time when there is no allocation
    start_time=""
  else
    # Set the start_time if nodes where allocated to the job
    start_time=$(echo "$control" | grep '^StartTime=' | cut -d= -f2)
  fi

  end_time=$(  echo "$control" | grep '^EndTime='   | cut -d= -f2)
elif [[ "$raw_control" == "slurm_load_jobs error: Invalid job id specified" ]]; then
  # Fallback to sacct if scontrol does not recognise the ID
  raw_acct=$(sacct --noheader --parsable --jobs "$1" --format State,Reason,START,END,AllocTRES)
  exit_status="$?"
  acct=$(echo "$raw_acct" | head -n1)
  cat <<EOF

sacct:
$raw_acct
EOF

  # Transition the job to "UNKNOWN" is sacct has no record of it
  if [[ "$exit_status" -eq 0 ]] && [ -z "$acct" ]; then
    state="UNKNOWN"
    start_time=''
    end_time=''
    reason=''

  # Extract the output from sacct
elif [[ "$exit_status" -eq 0 ]]; then
  # sacct sometimes tacks info onto the end of the state
  state=$(echo "$acct" | cut -d'|' -f1 | cut -d' ' -f1)
  reason=$(echo "$acct" | cut -d'|' -f2)
  if [ "$(echo "$acct" | cut -d'|' -f5)" ]; then
    # Set the start_time if any trackable resources where allocated to the job
    start_time=$(echo "$acct" | cut -d'|' -f3)
  else
    # Skip setting the start_time when there are no allocated TRESS
    start_time=""
  fi
  end_time=$(echo "$acct" | cut -d'|' -f4)

  # Exit the monitor process if sacct fails to prevent the job being updated
  else
    echo "$sacct" >&3
    exit "$exit_status"
  fi
else
  # Exit the monitor process if scontrol fails to prevent the job being updated
  exit "$exit_status"
fi

# Convert "Unknown" times to empty string
if [[ "$start_time" == "Unknown" ]] ; then
  start_time=""
fi
if [[ "$end_time" == "Unknown" ]] ; then
  end_time=""
fi

# Render and return the payload
echo '{}' | jq  --arg state "$state" \
                --arg reason "$reason" \
                --arg start_time "$start_time" \
                --arg end_time "$end_time" \
                "$template" | tr -d "\n"

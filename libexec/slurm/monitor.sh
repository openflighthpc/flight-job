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
control=$(scontrol show job "$1" 2>&1)
exit_status="$?"
if [[ "$exit_status" -eq 0 ]]; then
  # Determine the state and reason
  state=$(echo "$control" | grep -E "\s*JobState=" | sed "s/^\s*JobState=\([^ ]*\).*/\1/g")
  reason=$(echo "$control" | grep -E "Reason=" | sed "s/.*Reason=\(.*\)\sDependency=.*/\1/g")
  if [[ "$reason" == "None" ]]; then
    reason=""
  fi

  # Extract the times
  start_time=$(echo "$control" | grep -E ".*StartTime=" | sed "s/.*StartTime=\([^ ]*\).*/\1/g" )
  end_time=$(echo "$control" | grep -E ".*EndTime=" | sed "s/.*EndTime=\([^ ]*\).*/\1/g" )
elif [[ "$control" == "slurm_load_jobs error: Invalid job id specified" ]]; then
  # Fallback to sacct if scontrol does not recognise the ID
  acct=$(sacct --noheader --parsable --jobs "$1" --format State,Reason,START,END  | head -n1)
  exit_status="$?"

  # Transition the job to "UNKNOWN" is sacct has no record of it
  if [[ "$exit_status" -eq 0 ]] && [ -z "$acct" ]; then
    state="UNKNOWN"
    start_time=''
    end_time=''
    reason=''

  # Extract the output from sacct
  elif [[ "$exit_status" -eq 0 ]]; then
    state=$(echo "$acct" | cut -d'|' -f1)
    reason=$(echo "$acct" | cut -d'|' -f2)
    start_time=$(echo "$acct" | cut -d'|' -f3)
    end_time=$(echo "$acct" | cut -d'|' -f4)

  # Exit the monitor process if sacct fails to prevent the job being updated
  else
    echo "$sacct" >&3
    exit "$exit_status"
  fi
else
  # Exit the monitor process if scontrol fails to prevent the job being updated
  echo "$control" >&2
  exit "$exit_status"
fi

# Confirm times are in the right format and reject Unknown
# NOTE: This replaces "Unknown" times with empty string and converts times into RFC3339
format='^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d$'
if echo "$start_time" | grep -P "$format" ; then
  start_time="$start_time$(date +%:z)"
else
  start_time=""
fi
if echo "$end_time" | grep -P "$format" ; then
  end_time="$end_time$(date +%:z)"
else
  end_time=""
fi

# Render and return the payload
echo '{}' | jq  --arg state "$state" \
                --arg reason "$reason" \
                --arg start_time "$start_time" \
                --arg end_time "$end_time" \
                "$template" | tr -d "\n"

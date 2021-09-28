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

fail_with() {
    local msg code
    msg="$1"
    code=${2:-1}
    emit "${msg}" >&2
    exit ${code}
}

emit() {
    if [ ! -x "$(type -p fold)" ]; then
        if [ "$1" ]; then
            echo "$*" | fold -s
        else
            cat | fold -s
        fi
    else
        if [ "$1" ]; then echo "$*"; else cat; fi
    fi
}

check_progs() {
    local progs p r
    progs="$*"
    for p in ${progs}; do
        r=$(type -p $p)
        if [ $? != 0 -o ! -x "$r" ]; then
            fail_with "This system does not provide a required binary (${p})."
        fi
    done
}

assert_array_var() {
    declare -A | grep -q "declare -A $1" || fail_with "no $1 associative array declared"
}

assert_var() {
    if [[ -z ${1+x} ]] ; then
        fail_with "var $1 not declared"
    fi
}

# Read JSON template from stdin and report it to flight job.
report_metadata() {
    # Currently, we report the metadata as the last line of stdout.  It must
    # be on a single line.
    cat | tr -d "\n"
}

log_command() {
    cat <<EOF >&2

$1 output:
$(cat)
EOF
}

accumalate_json_array() {
    local array item
    array="$1"
    item="$2"
    jq --argjson item "$item" '. += [$item]' <<< "$array"
}

accumalate_json_object() {
    local object index item
    object="$1"
    index="$2"
    item="$3"
    jq --arg index "$index" --argjson item "$item" \
        '. + {($index): $item}' \
        <<< "$object"
}

source_parsers() {
    if [[ "$1" == "scontrol" ]] ; then
        source "${DIR}/scontrol_parser.sh"
    elif [[ "$1" == "sacct" ]] ; then
        source "${DIR}/sacct_parser.sh"
    else
        fail_with "unknown parser type $1"
    fi
}

# ==============================================================================
# State Mapping and helper functions
# ==============================================================================

declare -A STATE_MAP=(
  ["BF"]="FAILED"
  ["BOOT_FAIL"]="FAILED"
  ["CA"]="CANCELLED"
  ["CANCELLED"]="CANCELLED"
  ["CD"]="COMPLETED"
  ["COMPLETED"]="COMPLETED"
  ["CF"]="RUNNING"
  ["CONFIGURING"]="RUNNING"
  ["CG"]="RUNNING"
  ["COMPLETING"]="RUNNING"
  ["DL"]="FAILED"
  ["DEADLINE"]="FAILED"
  ["F"]="FAILED"
  ["FAILED"]="FAILED"
  ["NF"]="FAILED"
  ["NODE_FAIL"]="FAILED"
  ["OOM"]="FAILED"
  ["OUT_OF_MEMORY"]="FAILED"
  ["PD"]="PENDING"
  ["PENDING"]="PENDING"
  ["PR"]="FAILED"
  ["PREEMPTED"]="FAILED"
  ["R"]="RUNNING"
  ["RUNNING"]="RUNNING"
  ["RD"]="PENDING"
  ["RESV_DEL_HOLD"]="PENDING"
  ["RF"]="PENDING"
  ["REQUEUE_FED"]="PENDING"
  ["RH"]="PENDING"
  ["REQUEUE_HOLD"]="PENDING"
  ["RQ"]="PENDING"
  ["REQUEUED"]="PENDING"
  ["RS"]="RUNNING"
  ["RESIZING"]="RUNNING"
  ["RV"]="FAILED" # Currently jobs cannot be tracked if they change cluster
  ["REVOKED"]="FAILED" # as above
  ["SI"]="RUNNING"
  ["SIGNALING"]="RUNNING"
  ["SE"]="PENDING"
  ["SPECIAL_EXIT"]="PENDING"
  ["SO"]="RUNNING"
  ["STAGE_OUT"]="RUNNING"
  ["ST"]="RUNNING" # This is a bit of a misnomer, consider defining a new state
  ["STOPPED"]="RUNNING" # as above
  ["S"]="RUNNING" # as above
  ["SUSPENDED"]="RUNNING" # as above
  ["TO"]="FAILED"
  ["TIMEOUT"]="FAILED"
)

_parse_time() {
  if [[ "$1" != "Unknown" ]]; then
    printf "$1"
  fi
}

_parse_start_time() {
  if echo "RUNNING COMPLETED FAILED CANCELLED" | grep -q "$2"; then
    _parse_time "$1"
  fi
}

_parse_end_time() {
  if echo "COMPLETED FAILED CANCELLED" | grep -q "$2"; then
    _parse_time "$1"
  fi
}

_parse_estimated_start_time() {
  if [ "PENDING" == "$2" ]; then
    _parse_time "$1"
  fi
}

_parse_estimated_end_time() {
  if echo "RUNNING PENDING" | grep -q "$2"; then
    _parse_time "$1"
  fi
}

_parse_state() {
  if [ -n "${STATE_MAP["$1"]}" ]; then
    printf "${STATE_MAP["$1"]}"
  else
    printf "UNKNOWN"
  fi
}


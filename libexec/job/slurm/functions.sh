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

# ==============================================================================
# Library of functions suitable for any scheduler integration.  Nothing should
# be specific to any particular scheduler integration.
# ==============================================================================

# ------------------------------------------------------------------------------
# JSON manipulation functions.
# ------------------------------------------------------------------------------

# Add the $2 to the end of the JSON array given in $1.
json_array_append() {
    local array item
    array="$1"
    item="$2"
    jq --argjson item "$item" '. += [$item]' <<< "$array"
}

# Add the $3 to the JSON object given in $1 with key $2.
json_object_insert() {
    local object key item
    object="$1"
    key="$2"
    item="$3"
    jq --arg key "$key" --argjson item "$item" \
        '. + {($key): $item}' \
        <<< "$object"
}

# ------------------------------------------------------------------------------
# Parser helper functions.  These should be suitable to work with any
# scheduler integration.
# ------------------------------------------------------------------------------

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
    assert_assoc_array_var STATE_MAP
    if [ -n "${STATE_MAP["$1"]}" ]; then
        printf "${STATE_MAP["$1"]}"
    else
        printf "UNKNOWN"
    fi
}

# Parse stdin to a PARSE_RESULT.
#
# Requires suitable parser primitives to be available for the given stdin.
parse_task() {
    assert_assoc_array_var PARSE_RESULT
    local parse_input state

    parse_input="$(cat)"
    state="$(parse_state <<< "${parse_input}")"

    PARSE_RESULT[state]="${state}"
    PARSE_RESULT[scheduler_state]=$(parse_scheduler_state <<< "${parse_input}")
    PARSE_RESULT[reason]=$(parse_reason <<< "${parse_input}")
    PARSE_RESULT[start_time]=$(parse_start_time "${state}" <<< "${parse_input}")
    PARSE_RESULT[end_time]=$(parse_end_time "${state}" <<< "${parse_input}")
    PARSE_RESULT[estimated_start_time]=$(parse_estimated_start_time "$state" <<< "${parse_input}")
    PARSE_RESULT[estimated_end_time]=$(parse_estimated_end_time "$state" <<< "${parse_input}")
    PARSE_RESULT[stdout_path]=$(parse_stdout <<< "${parse_input}")
    PARSE_RESULT[stderr_path]=$(parse_stderr <<< "${parse_input}")
}

# ------------------------------------------------------------------------------
# Assertion helpers.  Fail early if certain assertions are not met for easier
# debugging.
# ------------------------------------------------------------------------------

# Fail unless arguments $* are all executable programs.
assert_progs() {
    local progs p r
    progs="$*"
    for p in ${progs}; do
        r=$(type -p $p)
        if [ $? != 0 -o ! -x "$r" ]; then
            fail_with "This system does not provide a required binary (${p})."
        fi
    done
}

# Fail unless $1 is an associative array.
assert_assoc_array_var() {
    declare -A | grep -q "declare -A $1" || fail_with "no $1 associative array declared"
}

# Fail unless $1 is defined.  The defined as the empty string is accepted.
assert_var() {
    if [[ -z ${1+x} ]] ; then
        fail_with "var $1 not declared"
    fi
}

# ------------------------------------------------------------------------------
# Miscellaneous utility functions
# ------------------------------------------------------------------------------

fail_with() {
    local msg code
    msg="$1"
    code=${2:255}
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

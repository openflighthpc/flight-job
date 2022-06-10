#!/bin/bash -l
#==============================================================================
# Copyright (C) 2021 Alces Flight Ltd.
#
# This work is licensed under a Creative Commons Attribution-ShareAlike
# 4.0 International License.
#
# See http://creativecommons.org/licenses/by-sa/4.0/ for details.
#==============================================================================
# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
#                        SLURM SUBMISSION SCRIPT
#                       AVERAGE QUEUE TIME: Short
# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
#  >>>> OPERATIONAL DIRECTIVES - change these as required
# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

#=====================
#  Working directory
#---------------------
# The following directive overrides the jobs working directory to the
# specified location.
#
# Alternatively, adding an additional comment marker will disable the
# override. Your job will then be executed in the directory from which
# it was submitted.
#
#SBATCH -D /home/vagrant

#=========================
#  Environment variables
#-------------------------
# When set to "ALL", this setting exports all variables present when
# the job is submitted.  Set to "NONE" to disable environment variable
# propagation, or a comma-separated list to be more selective.
#
#SBATCH --export=ALL

#================
#  Output files
#----------------
# Set an output file for messages generated by your job script
#
# Specify a path to a file to contain the output from the standard
# output stream of your job script. If you omit `-e` below,
# standard error will also be written to this file.
#
#SBATCH -o job-%j.output

# Set an output file for STDERR
#
# Specify a path to a file to contain the output from the standard
# error stream of your job script.
#
# This is not required if you want to merge both output streams into
# the file specified above.
#
##SBATCH -e job-%j.error

#============
#  Job name
#------------
# Set the name of your job - this will be shown in the process
# queue.
#
##SBATCH -J 

#=======================
#  Email notifications
#-----------------------
# Set the destination email address for notifications.  If not set,
# will send mail to the submitting user on the submission host.
#
##SBATCH --mail-user=your.email@example.com

# Set the conditions under which you wish to be notified.
# Valid options are: NONE, BEGIN, END, FAIL, REQUEUE, ALL (equivalent
# to BEGIN, END, FAIL, REQUEUE, and STAGE_OUT), STAGE_OUT (burst
# buffer stage out and teardown completed), TIME_LIMIT, TIME_LIMIT_90
# (reached 90 percent of time limit), TIME_LIMIT_80 (reached 80
# percent of time limit), TIME_LIMIT_50 (reached 50 percent of time
# limit) and ARRAY_TASKS (send emails for each array task). Multiple
# type values may be specified in a comma separated list.
# If not specified, will send mail if the job is aborted.
#
##SBATCH --mail-type ALL

#============
#  Deadline
#------------
# Set a deadline by which your job must complete.
#
# If Slurm is not able to schedule your job so that it will complete prior to
# deadline, it will either fail to submit, or if already submitted, will be
# cancelled.  In order for this to work correctly, the maximum runtime
# directive must be set.
#
# Set the deadline to 3 hours from now.
##SBATCH --deadline=now+3:0:0
#
# Set the deadline to 5pm.  Either 5pm today, or 5pm tomorrow if it is later
# than 5pm.
##SBATCH --deadline=17:00:00

# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
#  >>>> RESOURCE REQUEST DIRECTIVES - always set these
# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

#===================
#  Maximum runtime
#-------------------
# Expected RUNTIME
#
# Enter the expected runtime for your job.  Specification of a
# shorter runtime will cause the scheduler to be more likely to
# schedule your job sooner, but note that your job **will be
# terminated if it is still executing after the time specified**.
#
# A time limit of zero requests that no time limit be imposed.
# Format: one of "minutes", "minutes:seconds",
# "hours:minutes:seconds", "days-hours", "days-hours:minutes" and
# "days-hours:minutes:seconds". e.g. `30` for 30 minutes.
#SBATCH --time=30

#================
#  Memory limit
#----------------
# Expected HARD MEMORY LIMIT
#
# Enter the expected memory usage of your job.  Specification of a
# smaller memory requirement will cause the scheduler to be more
# likely to schedule your job sooner, but note that your job **may
# be terminated if it exceeds the specified allocation**.
#
# Note that this setting is specified in megabytes.
# e.g. specify `1024` for 1 gigabyte.
#
#SBATCH --mem=1024

#=========================
#  Resource requirements
#-------------------------
# Resources required for your job
#
# If your job has specific resource requirements specify them below.
# Specification of fewer resources will cause the scheduler to be more likely
# to scheduler your job sooner.
#
# e.g. GPUs, MICs, etc.
##SBATCH --gres gpu:1

#=====================
#  Specify partition
#---------------------
# The partition on which your job is to run
#
# Enter the partition that your job is to be submitted to.  You can find the
# list of available partitions by running the `sinfo` command from your
# cluster login.
##SBATCH -p nodes

# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
#  >>>> FLIGHT JOB ADAPTER
# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

#=================================
#  Standard Flight Job variables
#---------------------------------
# Standard environment variables.  When the job script is submitted through
# Flight Job, these variables will be set by Flight Job.  If not set, they
# default to sensible variables set by the scheduler.
FLIGHT_JOB_NAME="${FLIGHT_JOB_NAME:-$SLURM_JOB_NAME}"
FLIGHT_JOB_ID="${FLIGHT_JOB_ID:-${SLURM_ARRAY_JOB_ID:-$SLURM_JOB_ID}}"

#======================
#  Controls directory
#----------------------
# The controls directory is used internally to track various flight-job data
# files.  This is used to store the desktop session ID of the interactive
# session.
if [ "${CONTROLS_DIR}" != "" ]; then
  mkdir -p "${CONTROLS_DIR}"
fi

register_control() {
  local name
  local value
  name="$1"
  if [[ -p /dev/stdin ]]; then
      value="$( cat )"
  else
      value="$2"
  fi
  if [ -d "${CONTROLS_DIR}" ]; then
    if [ -z "${value}" ]; then
        :
    else
        echo "${value}" > "${CONTROLS_DIR}/${name}"
    fi
  else
    echo "CONTROLS_DIR has not been set or is not a directory" >&2
    echo "${name} ${value}"
  fi
}

#=========================
#  Session orchestration
#-------------------------
# Functions used to orchestrate the creation of your interactive session on a
# login node with X11 forwarding to a compute node.

tee_session_output() {
    if [ "${SESSION_OUTPUT}" == "" ] ; then
        SESSION_OUTPUT="${RESULTS_DIR}/session.output"
    fi
    tee -a "${SESSION_OUTPUT}"
}

register_scheduler_id() {
    stdbuf -oL sed -n 's/.*job \([0-9]*\) queued.*/\1/p' \
        | head -n 1 \
        | register_control "scheduler_id" 
}

# This function is ran twice.
#
# The first time it runs, it is on the login node, where it 
#
# 1. performs X11 forwarding preparation
# 2. performs Flight Job bookkeeping
# 3. requests an allocation from the scheduler such that this script (and
#    hence this function) will be executed on the allocated node.
# 4. `exit`s out of the entire job script thus preventing the job commands
#    from running on the login node.
#
# The second time it runs, it is on the compute node, where it
#
# 1. performs Flight Job bookkeeping
# 2. completes the X11 forwarding configuration
# 3. `return`s from the function, allowing the job commands to run on the
#    compute node.
#
# This might seem like a complicated way of doing things but it greatly
# reduces the complexity of the job workload presented to the job script
# author, and keeps a high level of consistency between the job scripts
# workloads.
request_allocation() {
    if [ -z $SLURM_JOBID ] ; then
        # This script is running on a login node.  We wan't to submit this
        # script to the scheduler via srun and then exit the script.

        local submit_status
        declare -a scheduler_args
        declare -a job_script_args
        declare arg_type=scheduler_args

        # Extract scheduler arguments from job script argument.
        for i in "$@" ; do
            case "$i" in
                "--")
                    arg_type=job_script_args
                    ;;
                *)
                    if [ "${arg_type}" == "scheduler_args" ] ; then
                        scheduler_args+=($i)
                    else
                        job_script_args+=($i)
                    fi
                    ;;
            esac
        done

        # Prepare X11 forwarding
        # Add our short hostname to the DISPLAY variable if we need to
        if [ `echo $DISPLAY | cut -d: -f1 | egrep -c [a-z]` -lt 1 ] ; then
            export DISPLAYNAME=`hostname -s`$DISPLAY
        else
            export DISPLAYNAME=$DISPLAY
        fi

        # Some Flight Job bookkeeping to allow the job to be monitored /
        # controlled.
        register_control "job_type" "BOOTSTRAPPING"
        register_control "submit_status" "0"

        # Long-winded construction of `srun` arguments to ensure that we don't
        # lose any quoting along the way.
        declare -a srun_args
        srun_args+=("--pty")
        for i in "${scheduler_args[@]}" ; do
            srun_args+=("$i")
        done
        srun_args+=("${BASH_SOURCE[0]}")
        srun_args+=("$DISPLAYNAME")
        for i in "${job_script_args[@]}" ; do
            srun_args+=("$i")
        done

        # Request an allocation from the scheduler.  The allocation will run
        # this script again on the allocated node.
        echo "srun ${srun_args[@]}" | tee_session_output
        srun "${srun_args[@]}" 2> >( tee >( register_scheduler_id ) | tee_session_output )
        submit_status=$?
        if [ ! -f "${CONTROLS_DIR}/scheduler_id" ] ; then
            # The scheduler_id hasn't been recorded.  We assume that the
            # job wasn't submitted to the scheduler successfully.  In
            # which case Flight Job cannot query the scheduler to discover
            # its status.  We set its status here.
            register_control "submit_status" ${submit_status}
            register_control "job_type" "FAILED_SUBMISSION"
            register_control "submit_stderr" "srun failed to submit job"
        else
            echo "Scheduler allocation has completed. Exiting..." | tee_session_output
            sleep 2
        fi

        # Either the allocation was succesful and has now completed or it was
        # rejected.  Either way we're done with this script on the login node.
        exit ${submit_status}

    else
        # The scheduler has allocated resources and the script is running for
        # a second time on one of the allocated nodes.

        # Some Flight Job bookkeeping to allow the job to be monitored /
        # controlled.
        register_control "scheduler_id" "$SLURM_JOB_ID"
        register_control "job_type" "BOOTSTRAPPING"

        # Setup the originator to expect our X connection.
        DISPLAYNAME=$1
        DISPLAYHOST=`echo $DISPLAYNAME | cut -d: -f1`
        this_hostname=`hostname -s`
        setxhost="ssh $DISPLAYHOST 'export DISPLAY=$DISPLAYNAME && xhost $this_hostname'"
        echo -ne "Enabling $DISPLAYHOST to accept our X-connection... " | tee_session_output
        eval $setxhost | tee_session_output
        export DISPLAY=$DISPLAYNAME

        # We return here to allow the rest of the job script, i.e., the
        # actualy workload to continue.
        return 0
    fi
}


# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
#  >>>> SET TASK ENVIRONMENT VARIABLES
# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# If necessary, set up further environment variables that are not
# specific to your workload here.
#
# Several standard variables, such as SLURM_JOB_ID, SLURM_JOB_NAME and
# SLURM_NTASKS, are made available by the scheduler.

# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
#  >>>> YOUR WORKLOAD
# ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

#===========================
#  Create results directory
#---------------------------
# By convention, job's submitted with `flight-job` are expected to save their
# results to RESULTS_DIR.  `flight-job` provides easy access to any files
# saved there.
#
# Your job can save its results anywhere you want, but if the results are
# saved outside of RESULTS_DIR, 'flight-job' will be unable to help you access
# your results.
#
# This directory should be accessible from both the node running the desktop
# session and the node that is allocated by the scheduler.
RESULTS_DIR="$(pwd)/${FLIGHT_JOB_NAME}-outputs/${FLIGHT_JOB_ID}"
register_control "results_dir" "${RESULTS_DIR}"
mkdir -p "$RESULTS_DIR"
echo "Your results will be stored in: $RESULTS_DIR" | tee_session_output

#===============================
#  Activate Flight Environment
#-------------------------------
source "${flight_ROOT:-/opt/flight}"/etc/setup.sh 2>&1 | tee_session_output


# Request an allocation from the scheduler.  When this function returns, the
# script will be running on the allocated node.
request_allocation "$@"
shift

# The script is now running on a node inside of a scheduler allocation.
# We can continue with the job commands.

#==============================
#  Activate Package Ecosystem
#------------------------------
{
# e.g.:
# flight env activate gridware
# module load apps/R
:
} 2>&1 | tee_session_output

#===============================
#  Application launch commands
#-------------------------------
# Customize this section to suit your needs.

echo "Executing job commands, current working directory is $(pwd)" 2>&1 \
    | tee_session_output

# REPLACE THE FOLLOWING WITH YOUR APPLICATION COMMANDS

if [ "$#" -gt 0 ] ; then
    echo "This is an example interactive job running a user given command: $@" 2>&1 \
        | tee_session_output
    "$@"
else
    echo "This is an example interactive job running a bash shell." 2>&1 \
        | tee_session_output
    bash
fi
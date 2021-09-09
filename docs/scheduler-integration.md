# Scheduler Integrations

By default, Flight Job integrates with the Slurm HPC scheduler.  It is
possible to configure Flight job to integrate with another scheduler.  To do
so involves three changes:

1. Write custom integration points for the scheduler.
2. Update any templates to generate appropriate directives for the new
   scheduler.
3. Configure Flight Job to use the new scheduler.

## Integration scripts

Flight Job uses two scripts to communicate with the scheduler and two other
files to map from scheduler-specific language to Flight Job specific language.

The following scripts need to be written:

* `submit.sh`: submits a job script to the scheduler and returns information
  about the submission and the scheduler job.
* `monitor.sh`: communicates with the scheduler to return details about any
  active jobs.

There are two other files that need to be created:

* A map from scheduler state names to Flight Job state names.
* An ERb template used to provide an integration point for generated job
  scripts, Flight Job and the scheduler.

The configuration section below details how to configure Flight Job to use the
new files.

### `submit.sh`

The `submit.sh` script receives a single argument: the path to the job script
to be submitted.  It should submit the job script to the scheduler and return
details about the submission and job in a Flight Job specific format.

The details are to be returned as a single line of JSON sent as the final line
of STDOUT.  The format for the [submission script
response](/lib/flight_job/models/job/submit_response_schema.yaml) is defined
using [JSON
Schema](https://json-schema.org/understanding-json-schema/index.html).

### `monitor.sh`

The `monitor.sh` script receives a single argument: the scheduler generated ID
of the job to be monitored.  It determines the current state of the scheduler
job and returns details in a Flight Job specific format.

The details are to be returned as a single line of JSON sent as the final line
of STDOUT.  The format for the [monitor script
response](/lib/flight_job/models/job/monitor_response_schema.yaml) is defined
using JSON Schema.

### State map

The [Slurm state map](/etc/job/state-maps/slurm.yaml) should prove to be
sufficient documentation to create a map for another scheduler.

### Adapter

The adapter Erb file maps certain scheduler-specific language to generic
Flight Job language.  The [Slurm adapter
file](/usr/share/job/adapter.slurm.erb) should be sufficient to create an
adapter for another scheduler.  Of note is the mechanism used to create the
`RESULTS_DIR` variable from Slurm specific variables.

## Template directives

Each template has a `directive.<scheduler>.erb` file which creates directives
suitable for `<scheduler>` from the answers to the templates questions.

A new directive file will need to be created for each template.  The [custom
templates](/docs/custom-templates.md) documentation and the [example
templates](/usr/share/job/templates/) might prove useful in doing so.

## Configuration

To configure Flight Job to use an alternative scheduler, edit the
configuration file and change the value for `scheduler`.

The default values for `submit_script_path`, `monitor_script_path`,
`adapter_script_path` and `state_map_path` all depend on the value of
`scheduler.  You may need to change these to match the paths of your
integration scripts.

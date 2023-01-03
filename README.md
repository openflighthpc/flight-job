# Flight Job

Generate job scripts from predefined templates and submit them to a HPC
scheduler.

## Overview

Flight Job facilitates the creation of complex job scripts from predefined
templates.  Job scripts are created by answering a number of questions defined
by the template.  Once created, Flight Job can submit the job script to the
cluster's HPC scheduler and provide support for managing the job and accessing
its results.

## Installation

### Installing with the OpenFlight package repos

Flight Job is available as part of the *Flight User Suite*.  This is the
easiest method for installing Flight Job and all its dependencies.  It is
documented in [the OpenFlight
Documentation](https://docs.openflighthpc.org/hpc_environment_usage/flight_overview/installing_flight_user_suite/).

### Manual Installation

#### Prerequisites

Flight Job is developed and tested with Ruby version `2.7.1` and `bundler`
`2.1.4`.  Other versions may work but currently are not officially supported.

#### Install Flight Job

The following will install from source using `git`.  The `master` branch is
the current development version and may not be appropriate for a production
installation. Instead a tagged version should be checked out.

```
git clone https://github.com/alces-flight/flight-job.git
cd flight-job
git checkout <tag>
bundle config set --local with default
bundle config set --local without development
bundle install
```

The manual installation of Flight Job comes preconfigured to run in
development mode.  If installing Flight Job manually for production usage you
will want to follow the instructions to [set the environment
mode](/docs/environment-modes.md) to `standalone`.

Use the script located at `bin/job` to execute the tool.

#### Install a HPC scheduler

By default, Flight Job ships with [Slurm](https://slurm.schedmd.com/)
integration scripts.  The integration scripts require
[jq](https://stedolan.github.io/jq/) to be installed.

These packages may be available for installation via your package manager.
Alternatively, you can follow the [slurm installation
instructions](https://slurm.schedmd.com/download.html) and the [jq
installation instructions](https://stedolan.github.io/jq/download/).  If
installing manually, make sure that the Slurm binaries and the jq binary are
on your PATH.


## Configuration

Flight Job comes preconfigured to work with Slurm without further
configuration.  Please refer to the [configuration file](etc/job.yaml)
for a full list of configuration options.


### Environment Modes

If Flight Job has been installed manually for production usage you
will want to follow the instructions to [set the environment
mode](docs/environment-modes.md) to `standalone`.

## Operation

A brief usage guide is given below.  More details can be found by running
`bin/job --help`.  If Flight Job was installed via the OpenFlight package
repos, you can read more detailed usage instructions by running `flight howto
show flight job`.

List the available templates.

```
bin/job list-templates 
```

Create a job script from the template `simple`.

```
bin/job create-script simple
```

List your scripts.

```
bin/job list-scripts
```

Submit the script `simple-1`.

```
bin/job submit simple-1
```

List your jobs.

```
bin/job list-jobs
```

Show details about the job `n0XYc-Vt`.

```
bin/job info-job n0XYc-Vt
```

View the standard output for job `n0XYc-Vt`.

```
bin/job view-job-stdout n0XYc-Vt
```

List the results directory for job `n0XYc-Vt`.

```
bin/job ls-job-results n0XYc-Vt
```

View the results file `test.output` for job `n0XYc-Vt`.

```
bin/job view-job-results n0XYc-Vt test.output
```

## Adding Custom Templates

Flight Job contains a number of [example templates](usr/share/job/templates/),
which are enabled by default.  Custom templates can be created by following
the [custom templates](docs/custom-templates.md) documentation.

## Scheduler Integrations

By default, Flight Job integrates with the Slurm HPC scheduler.  It is
possible to configure Flight job to integrate with another scheduler.  See the
[scheduler integrations](/docs/scheduler-integration.md) documentation for
details on how to do so.


## Periodic house keeping

Flight Job maintains its own record about the jobs it submits to the HPC
scheduler allowing Flight Job to provide details about a job long after the
HPC scheduler has discarded its own record.

Flight Job updates its records during normal usage and under normal usage
patterns it is expected that Flight Job will always be able to monitor the job
until it either completes or fails in some way.

However, if the HPC scheduler is configured so that it doesn't maintain job
records for very long, Flight Job may become unable to correctly update its
records about some jobs.  If this occurs, the job will transition to an
`UNKNOWN` state and certain data about it may not be available including its
start time, end time, the reason it failed (if indeeded it did).

The job's STDOUT, STDERR and results directory will be unaffected by this.

To work around this edge case, the `run-monitor` command can be periodically
ran for all users of Flight Job.  This could be done by creating a system
`cron` task or creating user `crontabs`.


# Versioning

This application uses [semver](https://semver.org/).  The [versioning
document](/docs/versioning.md) contains more details.

# Contributing

Fork the project. Make your feature addition or bug fix. Send a pull
request. Bonus points for topic branches.

Read [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

# Copyright and License

Eclipse Public License 2.0, see [LICENSE.txt](LICENSE.txt) for details.

Copyright (C) 2020-present Alces Flight Ltd.

This program and the accompanying materials are made available under
the terms of the Eclipse Public License 2.0 which is available at
[https://www.eclipse.org/legal/epl-2.0](https://www.eclipse.org/legal/epl-2.0),
or alternative license terms made available by Alces Flight Ltd -
please direct inquiries about licensing to
[licensing@alces-flight.com](mailto:licensing@alces-flight.com).

Flight Job is distributed in the hope that it will be
useful, but WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER
EXPRESS OR IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR
CONDITIONS OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR
A PARTICULAR PURPOSE. See the [Eclipse Public License 2.0](https://opensource.org/licenses/EPL-2.0) for more
details.

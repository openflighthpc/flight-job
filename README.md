# Flight Job

Generate a job script from a predefined template

## Prerequisite

This applications requires `ruby` version `2.7.1` and `bundler` `2.1.4`. This guide will assume that `ruby` and `bundler` are on your `PATH`, however absolute paths to the binaries are also supported.

By default, this application ships with `slurm` integration scripts. These scripts assume that `sbatch`,`scontrol`, etc.. are on your `PATH`. The integration scripts also require `jq` (version `1.6`) to be in your `PATH`. See [configuration](#configuration) for full details.

*Summary*:
* `ruby`
* `bundler`
* `slurm` - `scontrol`,`sbatch`,..
* `jq`

## Installation

*User Suite Install*

This package is available as part of the *OpenFlight - User Suite* as an rpm. This is the easiest method for installing `flight-job` and all required dependencies.

[Refer to the OpenFlight project for further details](https://use.openflighthpc.org/installing-user-suite/install.html).

*Manual Install*

Before proceeding, you will need a version of `ruby` `2.7.1`. You _may_ be able to run the application with a different ruby version, however you mileage may vary. [Refer to rvm documentation on how to install rub](https://rvm.io/).

By default, `flight-job` will need an install of `slurm` and `jq`. These packages maybe available via your package manager. Alternatively, they can be downloaded from: [slurm download](https://www.schedmd.com/downloads.php) and [jq download](https://stedolan.github.io/jq/download/).

`flight-job` should then be cloned via `git` and gems installed with `bundler`. The `master` branch is the current bleeding edge version and is not appropriate for production installs. Instead a tagged version should be checked out.

*Example Manual Slurm Installation*

```
# Install and configure slurm according to your requirments

# Install jq
cd /path/to/jq/bin
wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
mv jq-linux64 jq
chmod u+x jq

# jq will need to be on your PATH, consider adding to your .bashrc
export PATH=$PATH:$(pwd)

# Install flight-job
cd /path/to/parent-dir
git clone https://github.com/openflighthpc/flight-job
cd flight-job
git checkout <tag>

# Install the production gems
bundle install --with default --without development

# Install the development gems (optional)
bundle install --with default --with development
```

## Configuration

The github repo is preconfigured to run the application in development mode. This will cause the `flight_ROOT` environment variable to be ignored. The production behaviour can be achieved with:

```
export flight_ENVIRONMENT=production
export flight_ROOT=...
```
Please refer to the [reference configuration](etc/job.yaml) for a full list of configuration options.

### Environment Overview

`flight-job` has three supported environments in which it can operate in `production`, `standalone`, and `development`. By default the git repo will be configured to use `development`. They can be summaries as:

* `production`  - Runs with the production gems and respects `flight_ROOT`,
* `standalone`  - Runs with the production gems but ignores `flight_ROOT`, or
* `development` - Runs with the development gems and ignores `flight_ROOT`.

A "production" install should use either the `production` or `standalone` environments. In `production` the `flight_ROOT` environment variable is used to expand relative paths. The `flight_ROOT` environment variable should be set when using the `production` environment; otherwise the behaviour is the same as `standalone`. For example, the `production` environment will use the following paths:

* `$flight_ROOT/etc/job.yaml`
* `$flight_ROOT/usr/share/job/templates`
* ... etc ...

Both the `standalone` and `development` environments will ignore `$flight_ROOT` environment variable. Instead the will expand the paths from the "install directory":

* `/path/to/flight-job/etc/job.yaml`
* `/path/to/flight-job/usr/share/job/templates`
* ... etc ...

The environment can be set by either setting `flight_ENVIRONMENT` or overriding the `.env.development` file:

```
# Either option will set the enviroment
export flight_ENVIRONMENT=<env>
echo flight_ENVIRONMENT=<env> > .env.development.local
```

### Adding Custom Templates

The `templates_dir` in the configuration specifies the location that templates should be stored. This will either be:

* `$flight_ROOT`/usr/share/job/templates, or
* `/path/to/flight-job/usr/share/job/templates`.

A `template` must contain a `metadata.yaml` and associated "script template". Please refer to the [example templates](usr/share/templates/simple) for the specification.

## Operation

The following will list the available templates
NOTE: The behaviour is undefined if no templates are available

```
flight job list
```

The copy command is used to copy a template to another directory. By default it will copy to the current directory using the original file name.

```
# Copy to the current directory
$ fight job copy simple.sh
Successfully copied the template to: /root/simple.sh

# Change the name
$ flight job copy simple.sh demo.sh
Successfully copied the template to: /root/demo.sh

# Change the directory
$ flight job copy simple.sh /tmp
Successfully copied the template to: /tmp/simple.sh

# Handles duplicate files
$ flight job copy simple.sh
Successfully copied the template to: /root/simple.sh.1

# Allows copy by index
$ flight job copy 3
Successfully copied the template to: /root/simple.sh.2
```

### Updating the Internal Job Cache

The "internal job cache" will be update on an ad hoc basis. This will typically be when `info-job` or `list-jobs` is ran.

Depending on your schedulers configuration, this may result in inconsistent updating behaviour. The external scheduler may periodically purge its records of historic jobs; preventing `flight-job` updating its internal cache. In the case of the default `slurm` scripts, the `jobs` will be transitioned into an `UNKNOWN` state (\*\*).

To prevent this, the `run-monitor` command should be ran periodically for each user which has submitted jobs via `flight-job`. This can be done using `crontabs` or other appropriate deamon. 

\*\* NOTE: Custom `scheduler` implementations should also transition missing jobs to an `UNKNOWN` state. Failure to do so will cause them to get stuck in the "last known state".

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

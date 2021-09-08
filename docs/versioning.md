# Versioning

## CLI

This application uses [semver](https://semver.org/) to version the command
line interface. The current version is given within
[version.rb](/lib/flight_job/version.rb) or by running `bin/job --version`.

The current version covers changes to the public command line interface.

The following changes to the CLI are considered breaking changes and will only
be done as part of a major version release.

* Removing a command or alias.
* Removing a positional argument to a command.
* Changing the order of positional arguments to a command.
* Removing an option to a command.
* Changing the column order of the machine readable\* `list*` and `info*`
  outputs.
* Removing keys from the `--json` output.
* Renaming keys in the `--json` output.

The following changes to the CLI are not considered breaking changes.  They
may be done in a minor release.

* Adding a command or alias.
* Adding a positional argument to a command provided it does not break usage
  of that command without the new position argument.
* Adding an option to a command.
* Adding new columns to the machine readable\* `list*` and `info*` outputs.
* Adding keys to the `--json` output.

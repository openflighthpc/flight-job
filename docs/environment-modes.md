## Environment Modes

Flight Job has three supported environment modes in which it can operate:
`production`, `standalone`, and `development`.

* `production`:  Used when installed via the OpenFlight repos.
* `standalone`:  Used for a manual installation intended for production.
* `development`: Used for a manual installation intended for development. 


### Production environment mode

This mode is automatically selected when Flight Job is installed from the
OpenFlight repos.  The configuration file will be loaded from
`${flight_ROOT}/etc/job.yaml`.  Any relative paths in the configuration file
are expanded from `${flight_ROOT}`.


### Standalone environment mode

This mode is to be used for a manual installation intended for production
usage.  The configuration file is loaded from a path relative to the Flight
Job installation directory.  Any relative paths in the configuration file are
expanded from the Flight Job installation directory.

For example, if the git repo was cloned to, say, `/opt/flight-job`, the
configuration file would be loaded from `/opt/flight-job/etc/job.yaml` and,
the relative path for the `templates_dir` (`usr/share/job/templates`) would be
expanded to `/opt/flight-job/usr/share/job/templates`.

There are two mechanisms by which standalone mode can be activated, either
of which is sufficient.

* Create the file `.env.development.local` containing the line
  `flight_ENVIRONMENT=standalone`.
  ```
  echo flight_ENVIRONMENT=standalone > .env.development.local
  ```
* Export the environment variable `flight_ENVIRONMENT` set to `standalone`.
  ```
  export flight_ENVIRONMENT=standalone
  ```

### Development environment mode

This mode is to be used for a manual installation intended for development of
Flight Job.  The configuration file is loaded from a path relative to the
Flight Job installation directory.  Any relative paths in the configuration
file are expanded from the Flight Job installation directory.

So if the git repo was cloned to, say, `/opt/flight-job`, the configuration
file would be loaded from `/opt/flight-job/etc/job.yaml` and any relative
paths expanded from `/opt/flight-job`.  E.g., by default the templates would
be loaded from `/opt/flight-job/usr/share/job/templates`.

This is the default environment mode for a manual installation.

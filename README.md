# Flight Job

Generate a job script from a predefined template

## Installation

Requires a modern-ish version of ruby circa `2.7`

## Configuration

[See the reference config](etc/config.reference)

By default the job templates need to be stored in: `var/templates`

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

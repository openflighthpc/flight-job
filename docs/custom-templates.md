# Adding Custom Templates

The list of templates available are loaded from the directory given by the
`templates_dir` configuration.  By default, these will be the [example
templates](/usr/share/job/templates/) that ship with Flight Job.  If they are
not suitable, you can change `templates_dir` to some other directory and
create your own templates in that directory.

## Different templates for different users

The list of available templates can be configured independently for each user.
To do so, set the `templates_dir` configuration appropriately for each user in
their user-specific configuration file, `~/.config/flight/job.yaml`.

If `templates_dir` is not set for a user, the value set in the global
configuration file will be used.

## Template format

Each template is contained in its own subdirectory of `templates_dir` and
contains the following files:

* `metadata.yaml`: metadata about the template along with any questions used
  to generate a job script.
* `directives.<scheduler>.erb`: an
  [ERb](https://ruby-doc.org/stdlib-2.7.1/libdoc/erb/rdoc/ERB.html) file
  rendering to directives suitable for `<scheduler>`.
* `submit.yaml.erb`: an ERb file rendering to a YAML file specifying command
  line arguments to the scheduler submission tool (e.g., `sbatch`) and the job
  script.
* `workload.erb`: an ERb file rendering to the job script workload.

### `metadata.yaml`

`metadata.yaml` contains three sections:  general metadata about template, the
template's "generation-time" questions and the template's "submission-time"
questions.  [Full documentation for the template
questions](template-questions.md) is elsewhere.  [Complete documentation of
template tags](template-tags.md) can be found elsewhere.

A commented example of the metadata is below.  The required keys are
`version`, `name`, `synopsis`, `copyright`, `license` and
`generation_questions`.

```yaml
# The schema version for this template.  Currently, only version `0` is
# supported.
version: 0

# The name of the template.
name: Example template

# A brief single-line description of the template.
synopsis: An example template that exists for illustrative purposes.

# A more detailed description of the template, possibly spanning multiple
# lines.
description: |
  This is an example template that has been created to illustrate the template
  file format.

  A useful description would detail how to use the template and the job
  scripts that it creates.

  The Flight Job Webapp supports rendering
  [Markdown](https://www.markdownguide.org/) in this descripton.

# The copyright and license for this template.
copyright: Copyright (C) 2021 Alces Flight Ltd.
license: Creative Commons Attribution-ShareAlike 4.0 International

# The relative sort order for the template.  Templates with lower values
# appear before templates with higher values.
priority: 100

# The name of the job script that is generated.  This will also be the default
# name of the job submitted to the scheduler.
script_template: simple.sh

# Used to control some aspects of how a template is rendered into a job
# script.  The Flight Job Webapp also uses these to control some visual
# identifiers.  A link to more documentation on tags is given above.
tags:
  - script:type=batch

generation_questions: ...
submission_questions: ...
```

### `directives.<scheduler>.erb`

The `directives.<scheduler>.erb` file is an ERb template.  When it is rendered
the generation questions and their answers will be available.  It is expected
to render to a set of scheduler directives suitable for inclusion in a job
script submitted to `<scheduler>`.  It will be used as the initial section of
the generated job script.

The generation questions and the answers to them are made available under the
following keys.

* `questions.<question id>.answer`: evaluates to the answer provided to the
  question with `id` `<question id>`.
* `questions.<question id>.default`: evaluates to the default answer specified
  for the question with `id` `<question id>`.

An example directives file is given below for the Slurm scheduler.  It
demonstrates a number of things:

1. Dynamic directives can be created that are not dependent on any questions.
   See the working directory directive.
2. Directives can be set involving multiple questions.  See the job name
   directive.
3. Further processing of the answer to question is possible.  See the job name
   directive.
4. Directives can be conditionally included.  See the dependencies directive.

```erb
#!/bin/bash -l

#=====================
#  Working directory
#---------------------
#SBATCH -D <%= File.expand_path("~") %>

#============
#  Job name
#------------
#SBATCH -J example-<%=
  File.basename(questions.input_filename.answer.to_s, '.txt')
%>-<%=
  questions.job_type.answer.to_s
%>

#=====================
#  Specify partition
#---------------------
<% if questions.job_type.answer.to_s == "lines" -%>
#SBATCH -p lines
<% else -%>
#SBATCH -p default
<% end -%>

<% if questions.await_job.answer.to_s != "" -%>
#================
#  Dependencies
#----------------
# Wait for the completion of job <%= questions.await_job.answer %> prior to starting.
#SBATCH --dependency=afterok:<%= questions.await_job.answer %>
<% end -%>
```

### `workload.erb`

The `workload.erb` file is an ERb template which will be rendered in the same
environment as `directives.<scheduler>.erb` (see above for details on how to
access the answers to questions).

An example workload file is given below.


```erb
INPUT_FILE="<%= questions.input_filename.answer %>"
WC_OPTIONS="<%= questions.job_type.answer == 'lines' ? '-l' : '-w' %>"

echo "There are..."
wc ${WC_OPTIONS} "${INPUT_FILE}" | cut -f 1 -d ' '
echo "<%= questions.job_type.answer %> in ${INPUT_FILE}."
```

## Resultant job script

To complete the example, if a template with the above questions,
`directives.slurm.erb` and `workload.erb` were to be rendered with the
following answers for the user `flight`.

* `input_filename` = `lorem.txt`.
* `job_type` = `words`.

The resultant job script would be

```sh
#!/bin/bash -l

#=====================
#  Working directory
#---------------------
#SBATCH -D /home/flight

#============
#  Job name
#------------
#SBATCH -J example-lorem-lines

#=====================
#  Specify partition
#---------------------
#SBATCH -p lines


INPUT_FILE="lorem.txt"
WC_OPTIONS="-w"

echo "There are..."
wc ${WC_OPTIONS} "${INPUT_FILE}" | cut -f 1 -d ' '
echo "words in ${INPUT_FILE}."
```

### `submit.yaml.erb`

The `submit.yaml.erb` file is an ERb template will will be rendered in a
similar environment as `directives.<scheduler>.erb`.  However, the template's
submission questions and their answers are made available instead of the
template's generation questions.

The resultant YAML is expected to have the following structure:

```yaml
scheduler:
  # An array of command line arguments that will be given to the scheduler
  # submission tool, e.g., `sbatch`.
  args: []
job_script:
  # An array of command line arguments that will be given to the job script.
  args: []
```

An example `submit.yaml.erb` file is given below:

```yaml
<%
  scheduler_args = []
  job_script_args = []

  if !questions.job_name.answer.blank?
    scheduler_args << "--job-name"
    scheduler_args << questions.job_name.answer
  end

  if !questions.max_runtime.answer.blank?
    scheduler_args << "--time"
    scheduler_args << questions.max_runtime.answer
  end

  if !questions.sim_file.answer.blank?
    job_script_args << questions.sim_file.answer
  end
-%>
---
scheduler:
  args:
<% scheduler_args.each do |arg| -%>
    - "<%= arg %>"
<% end -%>

job_script:
  args:
<% job_script_args.each do |arg| -%>
    - "<%= arg %>"
<% end -%>
```

If this file were to be rendered with the following answers:

* `max_runtime` = `3`.
* `sim_file` = `/tmp/my.sim`

The resultant YAML file would be

```yaml
scheduler:
  args:
    - "--time"
    - "3"
job_script:
  args:
    - "/tmp/my.sim"
```

Such a file would result in a job script being submitted with the following
command line:

```sh
sbatch --time 3 /path/to/job/script.sh /tmp/my.sim
```

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
* `workload.erb`: an ERb file rendering to the job script workload.

### `metadata.yaml`

`metadata.yaml` contains two sections.  The first is the general metadata
about template, and the second are the template's questions.

A commented example of the metadata is below.  The required keys are
`version`, `name`, `synopsis`, `copyright`, `license` and
`generation_questions` (more on this later).

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
# identifiers.
#
# If the template is for an interactive job it should set the tags:
# `script:type=interactive` and `session:type=desktop`.
#
# If the template is for an array batch job it should set the tags:
# `script:type=batch` and `script:workload=array`.
#
# If the template is for a non-array batch job it should set the tags:
# `script:type=batch`.
tags:
  - script:type=batch

generation_questions: ...
```

#### Template questions

A template also contains a number of questions that are asked when a job
script is generated from it.  The questions are listed in `metadata.yaml`
under the key `generation_questions`.  The questions will be asked in the
order that they are listed in the `metadata.yaml` file.

The basic format for questions is:

```yaml
generation_questions:
    # A unique identifier for the question.
  - id: ""

    # A brief one-line description of what is being asked.
    text: ""

    # A more detailed description of what is being asked, possibly spanning
    # multile lines.
    description: >

    # The default value, if any.  Currently, the default value must be either
    # a string or an array of strings.
    default: ""

    # A description of how to format the question when presenting it to the
    # user.
    format:
      type: ""

    # The `ask_when` key is optional and indicates that this question is
    # conditionally asked.
    ask_when:
      value: question.<question id>.answer
      eq: ""

```

The `id`, `text`, `description` and `default` are all self-explanatory.  The
`format` and `ask_when` keys deserve more explanation.

The value of the `format` key is an object with a `type` attribute.
Currently, the valid values for `type` are `text`, `select` and `multiselect`.

If `type` is either `select` or `multiselect` an `options` key must also be
given.  The value for `options` is an array of objects with `text` and `value`
keys.

The `ask_when` key is optional and is used to indicate that asking the
question is conditional.  The question will be asked if the answer to the
question referred to by `value` is equal to the value of the `eq` key.
Currently, the only type of value that can be queried is the answer to a
question and the only comparison is equality.  The example below will help to
clarify this.

Some complete question examples are given below:

---

A question asking for the job's working directory.  It accepts a single line
of text as its answer.

```yaml
generation_questions:
  - id: input_filename
    text: "Input filename (including .txt extension):"
    description: >
      The name of the input file to use.

      This should be the name of the file not the path to the file.  The file
      must be found in your home directory.
    default: 'data.txt'
    format:
      type: text
```

---

A question asking for the job type.  It allows the user to select one option
from a multiple of choices.

```yaml
  - id: job_type
    text: "Job type:"
    description: >
      The job type.
    default: 'lines'

    # Here `type: select` specifies to format the question as a multiple
    # choice.
    format:
      type: select
      # The `options` key details the available options.
      options:
          # `text` is the value presented to the user.
        - text: 'Lines'
          # `value` is the value used if this option is selected.
          value: 'lines'

        - text: 'Words'
          value: 'words'
```

Alternatively, the `type` `multiselect` can be used to allow the user to
select multiple options.  In this case the `default`, if given, must be an
array.

---

A question that is conditionally asked depending on the answer to a previous
question.  In this case it is only asked if the answer to the `job_type`
question was `solve`.  Currently, only answers to questions can be queried and
the only comparison is equality.

```yaml
  - id: await_job
    text: "ID of job to wait for before starting:"
    description: >
      Wait for job ID.
    format:
      type: text
      minimum: 1

    # The `ask_when` key indicates that this question is conditionally asked.
    # In this case, it will be asked when the answer to the question
    # `job_type` equals 'lines'.
    ask_when:
      value: question.job_type.answer
      eq: 'lines'

```

### `directives.<scheduler>.erb`

The `directives.<scheduler>.erb` file is an ERb template.  When it is rendered
the questions and their answers will be available.  It is expected to render
to a set of scheduler directives suitable for inclusion in a job script
submitted to `<scheduler>`.  It will be used as the initial section of the
generated job script.

The questions and the answers to them are made available under the following
keys.

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

# Template questions

A template contains a number of questions that are asked when a job script is
generated from it and a number of questions that are asked when the script is
submitted.

The questions asked when a job script is generated are listed in
`metadata.yaml` under the key `generation_questions` whilst those asked when a
job script is submitted are under the key `submission_questions`.

In both cases, the questions will be asked in the order that they are listed
in the `metadata.yaml` file.

The format for questions is the same for both generation and submission
questions.  For brevity, the rest of this document refers to generation
questions alone, but everything applies equally to submission questions.

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

    # A description of how to validate the answer given by the user.
    validate: {}

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


## Dynamic question defaults and options

Some aspects of a template's questions can be dynamically generated instead of
being hardcoded.  These include the default value and the options for select
and multiselect questions.

The syntax for dynamic defaults is 

```yaml
generation_questions:
  - <OTHER QUESTION ATTRIBUTES>
    dynamic_default:
      type: path_placeholder
      path: <PATH_CONTAINING_PLACEHOLDERS>
```

There is currently only a single type of dynamic default available, namely,
`path_placeholder`.

The syntax for path placeholders is `<identifier>` where `<identifier>` is an
entire "path segment".  E.g., the path `/some/path/<username>/somewhere`
contains the placeholder `<username>` whilst `/some/path_<username>/somewhere`
and `/some/path/<username>_somewhere` do not.

The only supported placeholder is `<username>` which is replaced with the
process's user's login name.


The syntax for dynamic options is

```yaml
generation_questions:
  - <OTHER QUESTION ATTRIBUTES>
    format:
      type: select
      dynamic_options:
        type: file_listing
        include_null: <true|false|string>
        glob: "*"
        format_path: <absolute|relative|basename>
        directories:
          - <PATH OPTIONALLY CONTAINING PATH PLACEHOLDERS>
          - ...
```

The only supported type of dynamic question is currently `file_listing`.  It
globs the specified directories with the specified glob.

Any files (not directories) that match the glob are included in the generated
list of options.  The text presented to the user for each generated option is
controlled by the `format_path` setting.  The text can be the `absolute` path
to the globbed file; the `relative` path from the directory under which it was
globbed; or its `basename`.

A "null" option can be included in the list of generated options by specifying
the `include_null` setting.  If set to a string, that string will be used as
the user-visible text for the null option.  If set to `true` the string
`(none)` will be used.

The directories to glob can optionally contain path placeholders.  They work
the same as described above for "Dynamic defaults".


## Validation

Validation can be added to each question to ensure that the answer is valid.
The validation syntax is similar to the [JSON
Schema](https://json-schema.org/) syntax.

The validation is given under the `validate` key.

### Validate the answer type

The type of the answer can be validated with the `type` key.

```yaml
generation_questions:
- <OTHER QUESTION ATTRIBUTES>
  validate:
    type: <string|number|integer|boolean|array>
```

### Validate the pattern of a string answer

If a string answer must match a certain patter, validation can be added
with the `pattern` and `pattern_error` keys.

```yaml
generation_questions:
- <OTHER QUESTION ATTRIBUTES>
  validate:
    type: string
    pattern: <regular expression to match against>
    pattern_error: <error message if the answer does not match the pattern>
```

### Validate an answer matches a known list of values

If the answer must be from a known list of values, validation can be added
with the `enum` key.  The example below is for string values, but this
validation can be used for any type of answer.

```yaml
generation_questions:
- <OTHER QUESTION ATTRIBUTES>
  validate:
    enum: [ "small", "medium", "large" ]
```

### Validate bounds on number and integer answers

If a number (inluding integer) answer must be within a minimum and maximum
value, validation can be added with the `minimum`, `maximum`,
`exclusive_minimum` and `exclusive_maximum` keys.  `exclusive_minimum` and
`exclusive_maximum` do not permit the values given, whilst `minimum` and
`maximum` do.

The example below allows for an answer that is greater than `0` and less than
or equal to `1024`.

```yaml
generation_questions:
- <OTHER QUESTION ATTRIBUTES>
  validate:
    type: integer
    exlusive_minimum: 0
    maximum: 1024
```



## Examples

A question asking for the `.dat` file to process.  The user will be presented
with a list of `.dat` files loaded from the specified directory.  They will be
able to select a single `.dat` file.

```yaml
generation_questions:
  - id: input_filename
    text: "Input filename (including .dat extension):"
    description: >
      The name of the input file to use.

      This should be the name of the file not the path to the file.
    dynamic_default:
      type: path_placeholder
      path: /mnt/data/<username>/data.dat
    format:
      type: select
      dynamic_options:
        type: file_listing
        include_null: false
        glob: "*.dat"
        format_path: "basename"
        directories:
          - /mnt/data/<username>
    validate:
      type: string
      pattern: "\.dat$"
      pattern_error: "must be a .dat file"
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

    validate:
      enum: [ 'lines', 'words' ]
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
      type: integer
      minimum: 1
    validate:
      type: integer
      minimum: 1


    # The `ask_when` key indicates that this question is conditionally asked.
    # In this case, it will be asked when the answer to the question
    # `job_type` equals 'lines'.
    ask_when:
      value: question.job_type.answer
      eq: 'lines'

```


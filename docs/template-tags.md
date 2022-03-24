# Template tags

The `tags` attribute for templates is a list of [triple
tags](https://en.wikipedia.org/wiki/Tag_(metadata)#Triple_tags) used to
control

1. The rendering of a template into a job script.
2. The submission of the job script to the scheduler.
3. Some UI elements.

We can consider a template to fall into one of two categories:

1. Batch job.
2. Interactive job.

A template for a batch job should set the tag `script:type=batch`.

A template for an interactive job should set the tags
`script:type=interactive`, `session:type=desktop` and either
`session:order=desktop:alloc` or `session:order=alloc:desktop`.

The `session:order` tag defines the order in which the scheduler job
allocation and the desktop session should be requested.

If the tag is set to `desktop:alloc`, first a desktop session will be started,
then from within that desktop session a request for an allocation will be made
to the scheduler.  This may result in the desktop session and scheduler
allocation being on different nodes.  Flight Job will ensure that X11
forwarding is correctly configured to support this.

If the tag is set to `alloc:desktop`, first a request for an allocation will
be made to the scheduler.  Then from within that allocation a desktop session
will be started.  This results in the desktop session running on a compute
node.

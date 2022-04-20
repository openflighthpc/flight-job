This script will submit multiple, similar jobs.  Each job will be allocated a
single core on the first available node. Use this when you wish to spawn
multiple jobs, making use of environment variables to differentiate each job.

## Environment variables

Job arrays will have additional environment variable set.

* `SLURM_ARRAY_JOB_ID` will be set to the first job ID of the array.
* `SLURM_ARRAY_TASK_ID` will be set to the job array index value.
* `SLURM_ARRAY_TASK_COUNT` will be set to the number of tasks in the job array.
* `SLURM_ARRAY_TASK_MAX` will be set to the highest job array index value.
* `SLURM_ARRAY_TASK_MIN` will be set to the lowest job array index value.

More details can be found in the [slurm
documentation](https://slurm.schedmd.com/job_array.html#env_vars).

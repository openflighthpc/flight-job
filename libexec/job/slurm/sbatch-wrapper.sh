#!/bin/bash

#-------------------------------------------------------------------------------
# NOTE:
#
# Please make installation specific modifications within this file.
# The last line printed to STDOUT for a successful deployment must be the
# response from sbatch:
#
# $ sbatch my-script
# > Submitted batch job XX
#-------------------------------------------------------------------------------
sbatch "$1"

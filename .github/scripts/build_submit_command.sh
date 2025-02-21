#!/usr/bin/env bash
###
### This script is intended to be used by github actions to build
### the qsub/sbatch/bash command required to submit a job on a given 
### system. It will attempt to source function definitions from 
### ./.github/scripts/submit_funcs_<system>.sh and run functions
### named submit_<system>_<app>
### Output from these functions must be of the form
### <APP>_SUBMIT_COMMAND='qsub -lncpus=...'
###
### Run like ./.github/scripts/submit_submit_command.sh <system> <app> >> $GITHUB_ENV
###
if [[ $# -ne 2 ]]; then
    echo 'Expected usage: ./.github/scripts/submit_submit_command.sh <system> <app> >> $GITHUB_ENV' >&2
    exit 1
fi

system="${1}"
app="${2}"
this_script=$( realpath $0 )
here="${this_script%/*}"

if [[ ! -f "${here}"/submit_funcs_"${system}".sh ]]; then
    echo "Error: required function definitions script submit_funcs_"${system}".sh is missing" >&2
    echo "       or ${system} is not a valid system" >&2
    exit 1
fi
source "${here}"/submit_funcs_"${system}".sh

if [[ $(type -t submit_${system}_${app}) == function ]]; then
    submit_${system}_${app}
else
    echo "Error: the requested submit function submit_${system}_${app} has not been defined" >&2
    echo "       or ${app} is not a valid application" >&2
    exit 1
fi
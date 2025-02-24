#!/usr/bin/env bash

function submit_setonix_petsc() {
    echo PETSC_SUBMIT_COMMAND="sbatch -p work -n 12 -N 1 -c 1 -t 2:00:00 --mem 48G --wait --export=REPO_PATH=${REPO_PATH}${QSUB_FLAG_64BIT} build-petsc.sh"
}

function submit_setonix_firedrake() {
    echo FIREDRAKE_SUBMIT_COMMAND="sbatch -p copy -n 1 -N 1 -c 1 -t 1:00:00 --mem 16G --wait --export=REPO_PATH=${REPO_PATH}${QSUB_FLAG_64BIT}${QSUB_FLAG_BRANCH} build-firedrake.sh"
}

function submit_setonix_gadopt() {
    echo GADOPT_SUBMIT_COMMAND="sbatch -p copy -n 1 -N 1 -c 1 -t 1:00:00 --mem 16G --wait --export=REPO_PATH=${REPO_PATH}${QSUB_FLAG_64BIT} build-gadopt.sh"
}
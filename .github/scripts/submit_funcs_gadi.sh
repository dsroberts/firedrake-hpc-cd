#!/usr/bin/env bash

function submit_gadi_petsc() {
    echo PETSC_SUBMIT_COMMAND="qsub -P xd2 -Wblock=true -lncpus=12,mem=48GB,walltime=2:00:00,jobfs=100GB,storage=gdata/xd2+scratch/xd2+gdata/fp50+scratch/fp50,ood=jupyterlab -v REPO_PATH=${REPO_PATH}${QSUB_FLAG_64BIT} build-petsc.sh"
}

function submit_gadi_firedrake() {
    echo FIREDRAKE_SUBMIT_COMMAND="qsub -P xd2 -Wblock=true -lncpus=1,mem=16GB,walltime=1:00:00,jobfs=100GB,storage=gdata/xd2+scratch/xd2+gdata/fp50+scratch/fp50 -q copyq -v REPO_PATH=${REPO_PATH}${QSUB_FLAG_64BIT}${QSUB_FLAG_BRANCH} build-firedrake.sh"
}

function submit_gadi_gadopt() {
    echo GADOPT_SUBMIT_COMMAND="qsub -P xd2 -Wblock=true -lncpus=1,mem=4GB,walltime=0:15:00,jobfs=100GB,storage=gdata/xd2+scratch/xd2+gdata/fp50+scratch/fp50 -q copyq -v REPO_PATH=${REPO_PATH}${QSUB_FLAG_64BIT} build-gadopt.sh"
}
#!/usr/bin/env bash
set -eu
### Recommended PBS job
### qsub -I -lncpus=1,mem=16GB,walltime=1:00:00,jobfs=100GB,storage=gdata/xd2+scratch/xd2+gdata/fp50 -q copyq
### Recommended SLURM job
### salloc -p work -n 1 -N 1 -c 1 -t 1:00:00 --mem 16G
###
### Use github action to checkout out firedrake repo, tar it up and
### copy to HPC system
###
### ==== SECTIONS =====
###
### 1.) Intialisation
module purge
this_script=$(realpath $0)
here="${this_script%/*}"
export APP_NAME="firedrake"
source "${here}/identify-system.sh"

### Load global definitions
source "${here}/functions.sh"

### Load machine-specific definitions
[[ -e "${here}/${FD_SYSTEM}/build-config.sh" ]] && source "${here}/${FD_SYSTEM}/build-config.sh"
[[ -e "${here}/${FD_SYSTEM}/functions.sh" ]] && source "${here}/${FD_SYSTEM}/functions.sh"

### 2.) Extract repo and gather commit/tag data
cd "${EXTRACT_DIR}"
if [[ ! -d "${EXTRACT_DIR}/${APP_NAME}" ]]; then
    tar -xf "${BUILD_STAGE_DIR}/${APP_NAME}.tar"
fi
pushd "${APP_NAME}"
### Tag with date of commit
export TAG=$(git show --no-patch --format=%cd --date=format:%Y%m%d)
### matches short commit length on github
export GIT_COMMIT=$(git rev-parse --short=7 HEAD)
export REPO_TAGS=($(git tag --points-at HEAD))
popd

export APP_BUILD_TAG=""
### Add any/all build type (e.g. 64bit) tags here
if [[ "${DO_64BIT}" ]]; then
    export APP_BUILD_TAG=${APP_BUILD_TAG}"-64bit"
fi

export APP_IN_CONTAINER_PATH="${APPS_PREFIX}/${APP_NAME}${APP_BUILD_TAG}"
export OVERLAY_EXTERNAL_PATH="${OVERLAY_BASE}/${APP_IN_CONTAINER_PATH#/*/}"
export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}${APP_BUILD_TAG}/${TAG}${MODULE_SUFFIX}"
export SQUASHFS_APP_DIR="${APP_NAME}${APP_BUILD_TAG}-${TAG}"

for p in "${MODULE_USE_PATHS[@]}"; do
    module use ${p}
done

### 3.) Load dependent modules
### This path might not exist inside of the container
if [[ -d "${MODULE_PREFIX}/petsc" ]]; then
    if [[ $( type -t __firedrake_pre_petsc_version_check ) == function ]]; then
        __firedrake_pre_petsc_version_check
    fi
    module use "${MODULE_PREFIX}"
    module load petsc${APP_BUILD_TAG}
    ### Get petsc module name
    export PETSC_MODULE=$(module -t list 2>&1 | grep petsc)
    export PETSC_TAG="${PETSC_MODULE#*/}"
    if [[ "${VERSION_TAG}" ]]; then
        export PETSC_DIR_SUFFIX="${PETSC_TAG//$VERSION_TAG/}"
    else
        export PETSC_DIR_SUFFIX="${PETSC_TAG}"
    fi
    module unload petsc${APP_BUILD_TAG}
fi

### 4.) Define 'inner' function(s)
function inner1() {

    ### i1.) Load modules & set environment
    for m in "${EXTRA_MODULES[@]}"; do
        module load ${m}
    done

    module load ${COMPILER_MODULE}
    module load ${MPI_MODULE}
    module load ${PY_MODULE}

    if [[ "${DO_64BIT}" ]]; then
        export OPTS_64BIT="--petsc-int-type int64"
    else
        export OPTS_64BIT=""
    fi

    export PETSC_DIR="${APPS_PREFIX}/petsc${APP_BUILD_TAG}/${PETSC_DIR_SUFFIX}"
    export PETSC_ARCH=default

    export PYOP2_CACHE_DIR=/tmp/pyop2
    export FIREDRAKE_TSFC_KERNEL_CACHE_DIR=/tmp/tsfc
    export XDG_CACHE_HOME=/tmp/xdg
    export FIREDRAKE_CI_TESTS=1

    export MPIRUN="${MPIRUN:-mpirun}"
    unset PYTHONPATH

    ### i2.) Install
    cd "${APP_IN_CONTAINER_PATH}/${TAG}"
    python${PY_VERSION} firedrake/scripts/firedrake-install --honour-petsc-dir --mpiexec=${MPIRUN} --mpicc=$( which mpicc ) --mpicxx=$( which mpicxx ) --mpif90=$( which mpif90 ) --no-package-manager ${OPTS_64BIT} --venv-name venv
    source "${APP_IN_CONTAINER_PATH}/${TAG}/venv/bin/activate"
    pip3 install jupyterlab assess gmsh imageio jupytext openpyxl pandas pyvista[all] shapely pyroltrilinos siphash24 jupyterview xarray trame_jupyter_extension pygplates

    ### i3.) Installation repair
    if [[ $( type -t __firedrake_post_build_in_container_hook ) == function ]]; then
        __firedrake_post_build_in_container_hook
    fi

}

function inner2() {

    source "/opt/${SQUASHFS_APP_DIR}/venv/bin/activate"
    pip3 install --target "${APP_IN_CONTAINER_PATH}/gadopt" --upgrade --no-deps gadopt

}

### 5.) Run inner function(s)
if [[ "$#" -ge 1 ]]; then
    if [[ "${1}" == '--inner' ]]; then
        inner1
        exit 0
    elif [[ "${1}" == '--inner2' ]]; then
        inner2
        exit 0
    fi
fi

### 6.) Pre-existing build check
if [[ -L "${APP_IN_CONTAINER_PATH}/${TAG}" ]]; then
    echo "This version of ${APP_NAME} is already installed - doing nothing"
    exit 0
fi

### 7.) Extract source & dependent squashfs into overlay
copy_squash_to_overlay "${APPS_PREFIX}/petsc${APP_BUILD_TAG}/petsc-${PETSC_TAG}.sqsh" "${SQUASHFS_PATH}/petsc${APP_BUILD_TAG}-${PETSC_DIR_SUFFIX}" "${OVERLAY_EXTERNAL_PATH%/*}/petsc${APP_BUILD_TAG}/${PETSC_DIR_SUFFIX}"

mkdir -p "${OVERLAY_EXTERNAL_PATH}/${TAG}"
mv "${APP_NAME}" "${OVERLAY_EXTERNAL_PATH}/${TAG}"

### 8.) Launch container build
bind_str=""
for bind_dir in "${bind_dirs[@]}"; do
    [[ -d "${bind_dir}" ]] && bind_str="${bind_str}${bind_dir},"
done
### Remove trailing comma
bind_str="${bind_str::-1}"
export BIND_STR="${bind_str}"

### Derive first directory of absolute path outside of the contaner
tmp="${APP_IN_CONTAINER_PATH:1}"
first_dir="/${tmp%%/*}"

module load "${SINGULARITY_MODULE}"

if [[ $( type -t __firedrake_pre_container_launch_hook ) == function ]]; then
    __firedrake_pre_container_launch_hook
fi

singularity -s exec --bind "${BIND_STR},${OVERLAY_BASE}:${first_dir}" "${BUILD_CONTAINER_PATH}/base.sif" "${this_script}" --inner

### 9.) Create squashfs
mkdir -p "${SQUASHFS_PATH}"
mv "${OVERLAY_EXTERNAL_PATH}/${TAG}" "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"

if [[ $( type -t __firedrake_extra_squashfs_contents ) == function ]]; then
    __firedrake_extra_squashfs_contents
fi

mksquashfs squashfs-root "${APP_NAME}.sqsh" -no-fragments -no-duplicates -no-sparse -no-exports -no-recovery -noI -noD -noF -noX -processors 8

### 10.) Create symlinks & modules
mkdir -p "${APP_IN_CONTAINER_PATH}"
ln -sf "/opt/${SQUASHFS_APP_DIR}" "${APP_IN_CONTAINER_PATH}/${TAG}"

cp "${APP_NAME}.sqsh" "${APP_IN_CONTAINER_PATH}/${APP_NAME}-${TAG}.sqsh"

make_modulefiles

mkdir -p "${APP_IN_CONTAINER_PATH}-scripts/${TAG}/overrides"
cp "${here}/launcher.sh" "${APP_IN_CONTAINER_PATH}-scripts/${TAG}"
cp "${here}/${FD_SYSTEM}/launcher_conf.sh" "${APP_IN_CONTAINER_PATH}-scripts/${TAG}"
cp "${here}"/overrides/* "${APP_IN_CONTAINER_PATH}-scripts/${TAG}/overrides/"
for i in "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"/venv/bin/*; do
    ln -s launcher.sh "${APP_IN_CONTAINER_PATH}-scripts/${TAG}/${i##*/}"
done

### 11.) Permissions
fix_apps_perms "${MODULE_FILE%/*}" "${APP_IN_CONTAINER_PATH}" "${APP_IN_CONTAINER_PATH}"-scripts

### 12.) Anything else?
singularity -s exec --bind "${BIND_STR},${first_dir}" --overlay="${APP_IN_CONTAINER_PATH}/${APP_NAME}-${TAG}.sqsh" "${BUILD_CONTAINER_PATH}/base.sif" "${this_script}" --inner2

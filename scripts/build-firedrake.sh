#!/usr/bin/env bash
set -e
### Recommended PBS job
### qsub -Wblock=true -lncpus=1,mem=16GB,walltime=1:00:00,jobfs=100GB,storage=gdata/xd2+scratch/xd2+gdata/fp50+scratch/fp50 -q copyq
### Recommended SLURM job
### sbatch -p copy -n 1 -N 1 -c 1 -t 1:00:00 --mem 16G --wait
###
### Use github action to checkout out firedrake repo, tar it up and
### copy to HPC system
###
### ==== SECTIONS =====
###
### 1.) Intialisation
module purge

if [[ ${REPO_PATH} ]]; then
    here="${REPO_PATH}/scripts"
    this_script="${here}/build-firedrake.sh"
else
    this_script=$(realpath "${0}")
    here="${this_script%/*}"
fi
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
if [[ "${BUILD_BRANCH}" ]]; then
    git checkout "${BUILD_BRANCH}"
    export TAG="${BUILD_BRANCH//\//_}"
else
    ### Tag with date of commit
    export TAG=$(git show --no-patch --format=%cd --date=format:%Y%m%d)
fi
### matches short commit length on github
export GIT_COMMIT=$(git rev-parse --short=7 HEAD)
export REPO_TAGS=($(git tag --points-at HEAD))
popd

export APP_BUILD_TAG=""
### Add any/all build type (e.g. 64bit) tags here
if [[ "${DO_64BIT}" ]]; then
    export APP_BUILD_TAG="${APP_BUILD_TAG}-64bit"
fi

export APP_IN_CONTAINER_PATH="${APPS_PREFIX}/${APP_NAME}${APP_BUILD_TAG}"
export OVERLAY_EXTERNAL_PATH="${OVERLAY_BASE}/${APP_IN_CONTAINER_PATH#/*/}"
export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}${APP_BUILD_TAG}/${TAG}${MODULE_SUFFIX}"
export SQUASHFS_APP_DIR="${APP_NAME}${APP_BUILD_TAG}-${TAG}"

[[ "${MODULE_USE_PATHS[@]}" ]] && module use "${MODULE_USE_PATHS[@]}"

### 3.) Load dependent modules
### This path might not exist inside of the container
if [[ -d "${MODULE_PREFIX}/petsc" ]]; then
    ### Prevent this block from altering the script environment
    while read key value; do
        [[ "${key}" == PETSC_MODULE ]] && export PETSC_MODULE="${value}"
        [[ "${key}" == PETSC_TAG ]] && export PETSC_TAG="${value}"
        [[ "${key}" == PETSC_DIR_SUFFIX ]] && export PETSC_DIR_SUFFIX="${value}"
    done < <(
        if [[ $(type -t __firedrake_pre_petsc_version_check) == function ]]; then
            __firedrake_pre_petsc_version_check
        fi
        module use "${MODULE_PREFIX}"
        module load petsc${APP_BUILD_TAG}
        ### Get petsc module name
        petsc_module=$(module -t list 2>&1 | grep petsc)
        echo PETSC_MODULE "${petsc_module}"
        petsc_tag="${petsc_module#*/}"
        echo PETSC_TAG "${petsc_tag}"
        if [[ "${VERSION_TAG}" ]]; then
            echo PETSC_DIR_SUFFIX "${petsc_tag//$VERSION_TAG/}"
        else
            echo PETSC_DIR_SUFFIX "${petsc_tag}"
        fi
    )
fi

### The Firedrake module does not incorporate a version tag, but it is required
### to load a petsc module, so unset that here
unset VERSION_TAG

### If we're building from a firedrake branch, move the module file so it does not
### appear unless specifically asked.
if [[ "${BUILD_BRANCH}" ]]; then
    module_dirname="${MODULE_PREFIX##*/}"
    export MODULE_PREFIX="${MODULE_PREFIX/$module_dirname/branch_$module_dirname}"
    export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}${APP_BUILD_TAG}/${TAG}${MODULE_SUFFIX}"
fi

### 4.) Define 'inner' function(s)
function inner1() {

    ### i1.) Load modules & set environment
    [[ "${EXTRA_MODULES[@]}" ]] && module load "${EXTRA_MODULES[@]}"

    module load "${COMPILER_MODULE}"
    module load "${MPI_MODULE}"
    module load "${PY_MODULE}"

<<<<<<< HEAD
    declare -a EXTRA_OPTS=()
    if [[ "${DO_64BIT}" ]]; then
        export EXTRA_OPTS+=( "--petsc-int-type int64" )
    fi
=======
    ### ?
    #if [[ "${DO_64BIT}" ]]; then
    #    export OPTS_64BIT="--petsc-int-type int64"
    #else
    #    export OPTS_64BIT=""
    #fi
>>>>>>> firedrake_pip_install

    export PETSC_DIR="${APPS_PREFIX}/petsc${APP_BUILD_TAG}/${PETSC_DIR_SUFFIX}"
    export PETSC_ARCH=default
    export HDF5_MPI=ON
    export HDF5_DIR="${PETSC_DIR}/${PETSC_ARCH}"
    export CC=$( which mpicc )
    export CXX=$( which mpicxx )
    export FC=$( which mpif90 )

    export PYOP2_CACHE_DIR=/tmp/pyop2
    export FIREDRAKE_TSFC_KERNEL_CACHE_DIR=/tmp/tsfc
    export XDG_CACHE_HOME=/tmp/xdg

    export MPIRUN="${MPIRUN:-mpirun}"
    mpirun_path=$(which "${MPIRUN}")
    export MPI_HOME=$(realpath "${mpirun_path%/*}"/..)
    unset PYTHONPATH

    ### i2.) Install
    cd "${APP_IN_CONTAINER_PATH}/${TAG}"
    python${PY_VERSION} -m venv venv
    source "${APP_IN_CONTAINER_PATH}/${TAG}/venv/bin/activate"
    pip3 install --no-binary h5py './firedrake[ci]'
    pip3 install jupyterlab assess gmsh imageio jupytext openpyxl pandas pyvista[all] shapely pyroltrilinos siphash24 jupyterview xarray trame_jupyter_extension pygplates

    ### i3.) Installation repair
    if [[ $(type -t __firedrake_post_build_in_container_hook) == function ]]; then
        __firedrake_post_build_in_container_hook
    fi

}

### 5.) Run inner function(s)
if [[ "$#" -ge 1 ]]; then
    if [[ "${1}" == '--inner' ]]; then
        inner1
        exit 0
    fi
fi

### 6.) Pre-existing build check
if ! [[ "${FD_INSTALL_DRY_RUN}" ]]; then
    if [[ -L "${APP_IN_CONTAINER_PATH}/${TAG}" ]]; then
        echo "This version of ${APP_NAME} is already installed - doing nothing"
        exit 0
    fi
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

### Derive first directory of absolute path outside of the container
tmp="${APP_IN_CONTAINER_PATH:1}"
first_dir="/${tmp%%/*}"

### Mount the directory we're binding over as <dir>-push-aside
### anything required from there can be symlinked in the
### pre_container_launch_hook.
export BIND_STR="${bind_str}${first_dir}:${first_dir}-push-aside"

module load "${SINGULARITY_MODULE}"

if [[ $(type -t __firedrake_pre_container_launch_hook) == function ]]; then
    __firedrake_pre_container_launch_hook
fi

singularity -s exec --bind "${BIND_STR},${OVERLAY_BASE}:${first_dir}" "${BUILD_CONTAINER_PATH}/base.sif" "${this_script}" --inner

### 9.) Create squashfs
mkdir -p "${SQUASHFS_PATH}"
mv "${OVERLAY_EXTERNAL_PATH}/${TAG}" "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"

if [[ $(type -t __firedrake_extra_squashfs_contents) == function ]]; then
    __firedrake_extra_squashfs_contents
fi

mksquashfs squashfs-root "${APP_NAME}.sqsh" -no-fragments -no-duplicates -no-sparse -no-exports -no-recovery -noI -noD -noF -noX -processors 8

if [[ "${FD_INSTALL_DRY_RUN}" ]]; then
    mkdir -p "${BUILD_STAGE_DIR}/${APP_NAME}${APP_BUILD_TAG}"
    cp "${APP_NAME}.sqsh" "${BUILD_STAGE_DIR}/${APP_NAME}-${TAG}.sqsh"
    ### Save modules to a dummy location
    export MODULE_FILE="${BUILD_STAGE_DIR}/${APP_NAME}${APP_BUILD_TAG}/${TAG}${MODULE_SUFFIX}"
    make_modulefiles
    exit 0
fi
### 10.) Create symlinks & modules
mkdir -p "${APP_IN_CONTAINER_PATH}"
ln -sf "/opt/${SQUASHFS_APP_DIR}" "${APP_IN_CONTAINER_PATH}/${TAG}"

cp "${APP_NAME}.sqsh" "${APP_IN_CONTAINER_PATH}/${APP_NAME}-${TAG}.sqsh"

make_modulefiles

mkdir -p "${APP_IN_CONTAINER_PATH}-scripts/${TAG}/overrides"
cp "${here}/launcher.sh" "${APP_IN_CONTAINER_PATH}-scripts/${TAG}"
cp "${here}/${FD_SYSTEM}/launcher_conf.sh" "${APP_IN_CONTAINER_PATH}-scripts/${TAG}"
[[ -d "${here}/${FD_SYSTEM}/overrides/" ]] && cp "${here}/${FD_SYSTEM}"/overrides/* "${APP_IN_CONTAINER_PATH}-scripts/${TAG}/overrides/"
for i in "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"/venv/bin/*; do
    ln -s launcher.sh "${APP_IN_CONTAINER_PATH}-scripts/${TAG}/${i##*/}"
done

### 11.) Permissions
fix_apps_perms "${MODULE_FILE%/*}" "${APP_IN_CONTAINER_PATH}" "${APP_IN_CONTAINER_PATH}"-scripts

### 12.) Anything else?
if [[ $(type -t __firedrake_post_build_hook) == function ]]; then
    __firedrake_post_build_hook
fi

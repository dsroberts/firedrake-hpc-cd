#!/usr/bin/env bash
set -e
### Recommended PBS job
### qsub -Wblock=true -lncpus=12,mem=48GB,walltime=2:00:00,jobfs=100GB,storage=gdata/xd2+scratch/xd2+gdata/fp50+scratch/fp50...
### Recommended SLURM job
### sbatch -p work -n 12 -N 1 -c 1 -t 2:00:00 --mem 48G --wait
###
### Use github action to checkout out petsc repo, tar it up and
### copy to HPC system
###
### ==== SECTIONS =====
###
### 1.) Intialisation
module purge

if [[ ${REPO_PATH} ]]; then
    here="${REPO_PATH}/scripts"
    this_script="${here}/build-petsc.sh"
else
    this_script=$(realpath $0)
    here="${this_script%/*}"
fi
export APP_NAME="petsc"
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
#export TAG=$( date +%Y%m%d )
### Tag with date of commit
export TAG=$(git show --no-patch --format=%cd --date=format:%Y%m%d)
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
export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}${APP_BUILD_TAG}/${TAG}${VERSION_TAG}${MODULE_SUFFIX}"
export SQUASHFS_APP_DIR="${APP_NAME}${APP_BUILD_TAG}-${TAG}"

### Some modules may be needed outside of the container
[[ "${MODULE_USE_PATHS[@]}" ]] && module use "${MODULE_USE_PATHS[@]}"

### 3.) Load dependent modules
### 4.) Define 'inner' function(s)
function inner() {

    ### i1.) Load modules & set environment
    [[ "${EXTRA_MODULES[@]}" ]] && module load "${EXTRA_MODULES[@]}"

    ### No quotes - some of these may need multiple modules to work
    module load "${COMPILER_MODULE}"
    module load "${MPI_MODULE}"
    module load "${PY_MODULE}"

    ### i2.) Install
    declare -a EXTRA_OPTS=()
    if [[ "${DO_64BIT}" ]]; then
        export EXTRA_OPTS+=( "--with-64-bit-indices" )
    fi

    cd "${APP_IN_CONTAINER_PATH}/${TAG}"

    export MPIRUN="${MPIRUN:-mpirun}"
    if [[ $(type -t get_system_specific_petsc_flags) == function ]]; then
        get_system_specific_petsc_flags
    fi

    "python${PY_VERSION}" ./configure PETSC_DIR="${APP_IN_CONTAINER_PATH}/${TAG}" PETSC_ARCH=default --with-mpiexec="${MPIRUN}" --with-fc=mpif90 COPTFLAGS="${COMPILER_OPT_FLAGS}" CXXOPTFLAGS="${COMPILER_OPT_FLAGS}" FOPTFLAGS="${COMPILER_OPT_FLAGS}" "${EXTRA_OPTS[@]}" --download-suitesparse --with-cxx=mpicxx --with-hwloc-dir=/usr --with-zlib --download-pastix --with-cc=mpicc --download-mumps --download-hdf5 --download-hypre --download-netcdf --download-pnetcdf --download-superlu_dist --with-shared-libraries=1 --with-c2html=0 --with-fortran-bindings=0 --download-metis --download-ptscotch --with-debugging=0 --download-bison "${SYSTEM_SPECIFIC_FLAGS[@]}" --with-make-np="${BUILD_NCPUS}"
    make PETSC_DIR="${APP_IN_CONTAINER_PATH}/${TAG}" PETSC_ARCH=default all

    ### i3.) Installation repair
    ###    a.) Resolve all shared object links
    if [[ $(type -t __petsc_post_build_in_container_hook) == function ]]; then
        __petsc_post_build_in_container_hook
    fi

}

### 5.) Run inner function(s)
if [[ "$#" -ge 1 ]]; then
    if [[ "${1}" == '--inner' ]]; then
        inner
        exit 0
    fi
fi

### 6.) Pre-existing build check
if ! [[ "${FD_INSTALL_DRY_RUN}" ]]; then
    if [[ -L "${APP_IN_CONTAINER_PATH}/${TAG}" ]]; then
        echo "This version of petsc is already installed - doing nothing"
        exit 0
    fi
fi

### 7.) Extract source & dependent squashfs into overlay
mkdir -p "${OVERLAY_EXTERNAL_PATH}"
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

if [[ $(type -t __petsc_pre_container_launch_hook) == function ]]; then
    __petsc_pre_container_launch_hook
fi

singularity -s exec --bind "${BIND_STR},${OVERLAY_BASE}:${first_dir}" "${BUILD_CONTAINER_PATH}/base.sif" "${this_script}" --inner

### 9.) Create squashfs
mkdir -p "${SQUASHFS_PATH}"
mv "${OVERLAY_EXTERNAL_PATH}/${TAG}" "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"

mksquashfs squashfs-root "${APP_NAME}.sqsh" -no-fragments -no-duplicates -no-sparse -no-exports -no-recovery -noI -noD -noF -noX -processors 8

if [[ "${FD_INSTALL_DRY_RUN}" ]]; then
    mkdir -p "${BUILD_STAGE_DIR}/${APP_NAME}${APP_BUILD_TAG}"
    cp "${APP_NAME}.sqsh" "${BUILD_STAGE_DIR}/${APP_NAME}-${TAG}${VERSION_TAG}.sqsh"
    export MODULE_FILE="${BUILD_STAGE_DIR}/${APP_NAME}${APP_BUILD_TAG}/${TAG}${MODULE_SUFFIX}"
    make_modulefiles
    exit 0
fi
### 10.) Create symlinks & modules
mkdir -p "${APP_IN_CONTAINER_PATH}"
ln -sf "/opt/${SQUASHFS_APP_DIR}" "${APP_IN_CONTAINER_PATH}/${TAG}"

cp "${APP_NAME}.sqsh" "${APP_IN_CONTAINER_PATH}/${APP_NAME}-${TAG}${VERSION_TAG}.sqsh"

make_modulefiles

### 11.) Permissions
fix_apps_perms "${MODULE_FILE%/*}" "${APP_IN_CONTAINER_PATH}"

### 12.) Anything else?
if [[ $(type -t __petsc_post_build_hook) == function ]]; then
    __petsc_post_build_hook
fi

#!/usr/bin/env bash
set -eu
### Recommended PBS job
### qsub -I -lncpus=12,mem=48GB,walltime=2:00:00,jobfs=100GB,storage=gdata/xd2+scratch/xd2+gdata/fp50...
###
### Use github action to checkout out petsc repo, tar it up and
### copy to gadi
###
### ==== SECTIONS =====
###
### 1.) Intialisation
this_script=$(realpath $0)
here="${this_script%/*}"
export APP_NAME="petsc"
source "${here}/identify-system.sh"

### Load global definitions
source "${here}/functions.sh"

### Load machine-specific definitions
[[ -e "${here}/${FD_SYSTEM}/build-config.sh" ]] && source "${here}/${FD_SYSTEM}/build-config.sh"
[[ -e "${here}/${FD_SYSTEM}/functions.sh" ]]    && source "${here}/${FD_SYSTEM}/functions.sh"

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
    export APP_BUILD_TAG=${APP_BUILD_TAG}"-64bit"
fi

export APP_IN_CONTAINER_PATH="${APPS_PREFIX}/${APP_NAME}${APP_BUILD_TAG}"
export OVERLAY_EXTERNAL_PATH="${APP_IN_CONTAINER_PATH//\/g/"${OVERLAY_BASE}"}"
export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}${APP_BUILD_TAG}/${TAG}${VERSION_TAG}"
export SQUASHFS_APP_DIR="${APP_NAME}${APP_BUILD_TAG}-${TAG}"

### 3.) Load dependent modules
### 4.) Define 'inner' function(s)
function inner() {

    ### i1.) Load modules & set environment
    for p in "${MODULE_USE_PATHS[@]}"; do
        module use ${p}
    done

    for m in "${EXTRA_MODULES[@]}"; do
        module load ${m}
    done

    module load "${COMPILER_MODULE}"
    module load "${MPI_MODULE}"
    module load "${PY_MODULE}"

    ### i2.) Install
    if [[ "${DO_64BIT}" ]]; then
        export OPTS_64BIT="--with-64-bit-indices"
    else
        export OPTS_64BIT=""
    fi

    cd "${APP_IN_CONTAINER_PATH}/${TAG}"

    get_scalapack_flags

    python${PY_VERSION} ./configure PETSC_DIR="${APP_IN_CONTAINER_PATH}/${TAG}" PETSC_ARCH=default --with-fc=mpif90 COPTFLAGS="${COMPILER_OPT_FLAGS}" CXXOPTFLAGS="${COMPILER_OPT_FLAGS}" FOPTFLAGS="${COMPILER_OPT_FLAGS}" ${OPTS_64BIT} --download-suitesparse --with-cxx=mpicxx --with-hwloc-dir=/usr --with-zlib --download-pastix --with-cc=mpicc --download-mumps --download-hdf5 --with-mpiexec=mpirun --download-hypre --download-netcdf --download-pnetcdf --download-superlu_dist --with-shared-libraries=1 --with-c2html=0 --with-fortran-bindings=0 --download-metis --download-ptscotch --with-debugging=0 --download-bison ${SCALAPACK_FLAGS} --with-make-np="${PBS_NCPUS}"
    make PETSC_DIR="${APP_IN_CONTAINER_PATH}/${TAG}" PETSC_ARCH=default all

    ### i3.) Installation repair
    ###    a.) Resolve all shared object links
    if [[ $( type -t __petsc_post_build_in_container_hook ) == function ]]; then
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
if [[ -L "${APP_IN_CONTAINER_PATH}/${TAG}" ]]; then
    echo "This version of petsc is already installed - doing nothing"
    exit 0
fi

### 7.) Extract source & dependent squashfs into overlay
mkdir -p "${OVERLAY_EXTERNAL_PATH}"
mv "${APP_NAME}" "${OVERLAY_EXTERNAL_PATH}/${TAG}"

### 8.) Launch container build
bind_str=""
for bind_dir in "${bind_dirs[@]}"; do
    [[ -d "${bind_dir}" ]] && bind_str="${bind_str}${bind_dir},"
done
### Remove trailing comma
bind_str="${bind_str::-1}"

module load singularity/"${SINGULARITY_MODULE}"
singularity -s exec --bind "${bind_str},${OVERLAY_BASE}:/g" "${BUILD_CONTAINER_PATH}/base.sif" "${this_script}" --inner

### 9.) Create squashfs
mkdir -p "${SQUASHFS_PATH}"
mv "${OVERLAY_EXTERNAL_PATH}/${TAG}" "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"

mksquashfs squashfs-root "${APP_NAME}.sqsh" -no-fragments -no-duplicates -no-sparse -no-exports -no-recovery -noI -noD -noF -noX -processors 8

### 10.) Create symlinks & modules
mkdir -p "${APP_IN_CONTAINER_PATH}"
ln -sf "/opt/${SQUASHFS_APP_DIR}" "${APP_IN_CONTAINER_PATH}/${TAG}"

cp "${APP_NAME}.sqsh" "${APP_IN_CONTAINER_PATH}/${APP_NAME}-${TAG}${VERSION_TAG}.sqsh"

mkdir -p "${MODULE_FILE%/*}"
copy_and_replace "${here}/../module/${FD_SYSTEM}/${APP_NAME}-base" "${MODULE_FILE}" APP_IN_CONTAINER_PATH COMPILER_MODULE TAG VERSION_TAG PYOP2_COMPILER_OPT_FLAGS
if [[ -z "${VERSION_TAG}" ]]; then
    copy_and_replace "${here}/../module/${FD_SYSTEM}/version-base" "${MODULE_FILE%/*}/.version" TAG
fi
cp "${here}/../module/${FD_SYSTEM}/${APP_NAME}-common" "${MODULE_FILE%/*}"

if [[ ! -e "${MODULE_FILE%/*}"/.modulerc ]]; then
    echo '#%Module1.0' >"${MODULE_FILE%/*}/.modulerc"
    echo '' >>"${MODULE_FILE%/*}/.modulerc"
fi

echo module-version "${APP_NAME}${APP_BUILD_TAG}/${TAG}${VERSION_TAG}" "${GIT_COMMIT}${VERSION_TAG}" >>"${MODULE_FILE%/*}/.modulerc"
for tag in "${REPO_TAGS[@]}"; do
    echo module-version "${APP_NAME}${APP_BUILD_TAG}/${TAG}${VERSION_TAG}" "${tag}${VERSION_TAG}" >>"${MODULE_FILE%/*}/.modulerc"
done
if [[ "${VERSION_TAG}" ]]; then
    echo module-version "${APP_NAME}${APP_BUILD_TAG}/${TAG}${VERSION_TAG}" "${VERSION_TAG:1}" >>"${MODULE_FILE%/*}/.modulerc"
fi

### 11.) Permissions
fix_apps_perms "${MODULE_FILE%/*}" "${APP_IN_CONTAINER_PATH}"

### 12.) Anything else?

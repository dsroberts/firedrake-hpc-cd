#!/usr/bin/env bash
set -eu
### Recommended PBS job
### qsub -I -lncpus=12,mem=48GB,walltime=2:00:00,jobfs=100GB,storage=gdata/xd2+scratch/xd2+gdata/vo05+scratch/vo05...
###
### Use github action to checkout out petsc repo, tar it up and
### copy to gadi
###
### ==== SECTIONS =====
###
### 1.) Intialisation
this_script=$( realpath $0 )
here="${this_script%/*}"
an="${this_script##*/}"
an="${an#*-}"
export APP_NAME="${an%.*}"
source "${here}/build-config.sh"
source "${here}/functions.sh"

### 2.) Extract repo and gather commit/tag data
cd "${PBS_JOBFS}"
if [[ ! -d "${PBS_JOBFS}/${APP_NAME}" ]]; then
    tar -xf "${BUILD_STAGE_DIR}/${APP_NAME}.tar"
fi
pushd "${APP_NAME}"
export TAG=$( date +%Y%m%d )
### matches short commit length on github
export GIT_COMMIT=$( git rev-parse --short=7 HEAD )
export REPO_TAGS=( $( git tag --points-at HEAD ) )
popd

export APP_IN_CONTAINER_PATH="${APPS_PREFIX}/${APP_NAME}"
export OVERLAY_EXTERNAL_PATH="${APP_IN_CONTAINER_PATH//\/g/"${OVERLAY_BASE}"}"
export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}/${TAG}"
export SQUASHFS_APP_DIR="${APP_NAME}-${TAG}"

declare -a MODULE_USE_PATHS=()

### 3.) Load dependent modules
### 4.) Define 'inner' function(s)
function inner() {

    ### i1.) Load modules & set environment
    for p in "${MODULE_USE_PATHS[@]}"; do
        module use ${p}
    done

    module load cmake/3.24.2
    ### pnetcdf will not compile against oneAPI fortran compiler
    ### with system autoconf - see https://community.intel.com/t5/Intel-Fortran-Compiler/ifx-2021-1-beta04-HPC-Toolkit-build-error-with-loopopt/td-p/1184181
    module load autoconf/2.72

    module load "${COMPILER_MODULE}"
    module load "${MKL_MODULE}"
    module load "${OMPI_MODULE}"
    module load "${PY_MODULE}"

    ### i2.) Install
    cd "${APP_IN_CONTAINER_PATH}/${TAG}"

    python${PY_VERSION} ./configure PETSC_DIR="${APP_IN_CONTAINER_PATH}/${TAG}" PETSC_ARCH=default --with-fc=mpif90 COPTFLAGS='-O3 -g -xCASCADELAKE' CXXOPTFLAGS='-O3 -g -xCASCADELAKE' FOPTFLAGS='-O3 -g -xCASCADELAKE' --download-suitesparse --with-cxx=mpicxx --with-hwloc-dir=/usr --with-zlib --download-pastix --with-cc=mpicc --download-mumps --download-hdf5 --with-mpiexec=mpirun --download-hypre --download-netcdf --download-pnetcdf --download-superlu_dist --with-shared-libraries=1 --with-c2html=0 --with-fortran-bindings=0 --download-metis --download-ptscotch --with-debugging=0 --download-bison --with-scalapack-include="${MKLROOT}/include" --with-scalapack-lib="-lmkl_scalapack_lp64 -lmkl_intel_lp64 -lmkl_sequential -lmkl_core -lmkl_blacs_openmpi_lp64 -lpthread -lm -ldl" --with-make-np="${PBS_NCPUS}"
    make PETSC_DIR="${APP_IN_CONTAINER_PATH}/${TAG}" PETSC_ARCH=default all

    ### i3.) Installation repair
    ###    a.) Resolve all shared object links
    resolve_libs "${APP_IN_CONTAINER_PATH}/${TAG}" "${APP_IN_CONTAINER_PATH}/${TAG}"

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
bind_str="${bind_str:: -1}"

module load singularity
singularity -s exec --bind "${bind_str},${OVERLAY_BASE}:/g" "${CONTAINER_PATH}/base.sif" "${this_script}" --inner

### 9.) Create squashfs
mkdir -p "${SQUASHFS_PATH}"
mv "${OVERLAY_EXTERNAL_PATH}/${TAG}" "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"

mksquashfs squashfs-root "${APP_NAME}.sqsh" -no-fragments -no-duplicates -no-sparse -no-exports -no-recovery -noI -noD -noF -noX -processors 8

### 10.) Create symlinks & modules
mkdir -p "${APP_IN_CONTAINER_PATH}"
ln -s "/opt/${SQUASHFS_APP_DIR}" "${APP_IN_CONTAINER_PATH}/${TAG}"

cp "${APP_NAME}.sqsh" "${APP_IN_CONTAINER_PATH}/${APP_NAME}-${TAG}.sqsh"

mkdir -p "${MODULE_FILE%/*}"
copy_and_replace "${here}/../module/${APP_NAME}-base" "${MODULE_FILE}" APP_IN_CONTAINER_PATH COMPILER_MODULE TAG
copy_and_replace "${here}/../module/version-base" "${MODULE_PREFIX}/${APP_NAME}/.version" TAG
cp               "${here}/../module/${APP_NAME}-common" "${MODULE_PREFIX}/${APP_NAME}"

if [[ ! -e "${MODULE_PREFIX}/${APP_NAME}"/.modulerc ]]; then
    echo '#%Module1.0' > "${MODULE_PREFIX}/${APP_NAME}/.modulerc"
    echo ''           >> "${MODULE_PREFIX}/${APP_NAME}/.modulerc"
fi
echo module-version "${APP_NAME}/${TAG}" "${GIT_COMMIT}" >> "${MODULE_PREFIX}/${APP_NAME}/.modulerc"
for tag in "${REPO_TAGS[@]}"; do
    echo module-version "${APP_NAME}/${TAG}" "${tag}" >> "${MODULE_PREFIX}/${APP_NAME}/.modulerc"
done

### 11.) Anything else?

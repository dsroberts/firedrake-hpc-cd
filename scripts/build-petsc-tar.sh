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
### Tag with upstream version - in the unlikely event
### of multiple tags in a petsc release, pick the first
repo_tags=($(git tag --points-at HEAD))
### Trim leading 'v'
export TAG="${repo_tags[0]//v/}"
### Always do default module for petsc
export DO_DEFAULT_MODULE=1
popd


for inplace in "-inplace" ""; do

    export APP_BUILD_TAG="${inplace}"
    ### Add any/all build type (e.g. 64bit) tags here
    if [[ "${DO_64BIT}" ]]; then
        export APP_BUILD_TAG="${APP_BUILD_TAG}-64bit"
    fi

    export APP_IN_CONTAINER_PATH="${APPS_PREFIX}/${APP_NAME}${APP_BUILD_TAG}"
    export BUILD_DIR_NAME="${APP_NAME}${APP_BUILD_TAG}-${TAG}"

    mkdir -p "${APP_IN_CONTAINER_PATH}"
    if [[ "${inplace}" ]]; then
        if [[ ! -d "${APP_IN_CONTAINER_PATH}/${TAG}${VERSION_TAG}" ]]; then
            tar -xf "${BUILD_STAGE_DIR}/${APP_NAME}.tar" -C "${APP_IN_CONTAINER_PATH}"
            mv "${APP_IN_CONTAINER_PATH}/${APP_NAME}" "${APP_IN_CONTAINER_PATH}/${TAG}${VERSION_TAG}"
        fi
        export PETSC_DIR="${APP_IN_CONTAINER_PATH}/${TAG}${VERSION_TAG}"
    else
        if [[ ! -d "${APP_REAL_INSTALL_DIR}/${BUILD_DIR_NAME}" ]]; then
            tar -xf "${BUILD_STAGE_DIR}/${APP_NAME}.tar" -C "${APP_REAL_INSTALL_DIR}"
            mv "${APP_REAL_INSTALL_DIR}/${APP_NAME}" "${APP_REAL_INSTALL_DIR}/${BUILD_DIR_NAME}"
        fi
        ln -sf "${APP_REAL_INSTALL_DIR}/${BUILD_DIR_NAME}" "${APP_IN_CONTAINER_PATH}/${TAG}"
        export PETSC_DIR="${APP_IN_CONTAINER_PATH}/${TAG}"
    fi

    ### Some modules may be needed outside of the container
    [[ "${MODULE_USE_PATHS[@]}" ]] && module use "${MODULE_USE_PATHS[@]}"

    ### 3.) Load dependent modules
    ### 4.) Define 'inner' function(s)
    ### function inner() {
    ### i1.) Load modules & set environment
    [[ "${EXTRA_MODULES[@]}" ]] && module load "${EXTRA_MODULES[@]}"

    module load "${COMPILER_MODULE}"
    module load "${MPI_MODULE}"
    module load "${PY_MODULE}"

    ### i2.) Install
    declare -a EXTRA_OPTS=()
    if [[ "${DO_64BIT}" ]]; then
        export EXTRA_OPTS+=( "--with-64-bit-indices" )
    fi

    cd "${APP_IN_CONTAINER_PATH}/${TAG}${VERSION_TAG}"

    export MPIEXEC="${MPIEXEC:-mpirun}"
    export MPICC="${MPICC:-mpicc}"
    export MPICXX="${MPICXX:-mpicxx}"
    export MPIF90="${MPIF90:-mpif90}"
    if [[ $(type -t get_system_specific_petsc_flags) == function ]]; then
        get_system_specific_petsc_flags
    fi

    ### output from firedrake-configure --no-package-manager --petscconf:
    ### --with-c2html=0 --with-debugging=0 --with-fortran-bindings=0 --with-shared-libraries=1 --with-strict-petscerrorcode PETSC_ARCH=arch-firedrake-default --COPTFLAGS='-O3 -march=native -mtune=native' --CXXOPTFLAGS='-O3 -march=native -mtune=native' --FOPTFLAGS='-O3 -march=native -mtune=native' --download-bison --download-fftw --download-hdf5 --download-hwloc --download-metis --download-mumps --download-netcdf --download-pnetcdf --download-ptscotch --download-scalapack --download-suitesparse --download-superlu_dist --download-zlib --download-hypre
    ### Key differences between firedrake-configure and the command below
    ###  - Per system definitions of compilers & compiler options (--with-cc=, --with-cxx=, --with-fc= and --with-mpiexec= are provided)
    ###  - HPC systems are expected to provide hwloc and zlib (--download-hwloc and --download-zlib replaced with --with-hwloc and --with-zlib)
    ###  - Flexibility when selecting fftw/blas/lapack/scalapack implementations. The per-system get_system_specific_flags function sets fftw/blas/lapack/scalapack options
    ###    Optimised libraries (MKL, BLIS, etc) will be preferred over reference implementations
    "python${PY_VERSION}" ./configure PETSC_DIR="${PETSC_DIR}" PETSC_ARCH=default --with-cc="${MPICC}" --with-cxx="${MPICXX}" --with-fc="${MPIF90}" --with-mpiexec="${MPIEXEC}" COPTFLAGS="${COMPILER_OPT_FLAGS}" CXXOPTFLAGS="${COMPILER_OPT_FLAGS}" FOPTFLAGS="${COMPILER_OPT_FLAGS}" "${EXTRA_OPTS[@]}" --with-c2html=0 --with-debugging=0 --with-fortran-bindings=0 --with-shared-libraries=1 --with-strict-petscerrorcode --download-bison --download-hdf5 --with-hwloc --download-metis --download-mumps --download-netcdf --download-pnetcdf --download-ptscotch --download-suitesparse --download-superlu_dist --with-zlib --download-hypre "${SYSTEM_SPECIFIC_FLAGS[@]}" --with-make-np="${BUILD_NCPUS}"

    make PETSC_DIR="${PETSC_DIR}" PETSC_ARCH=default all

    ### i3.) Installation repair
    ###    a.) Resolve all shared object links
    if [[ $(type -t __petsc_post_build_in_container_hook) == function ]]; then
        __petsc_post_build_in_container_hook
    fi

    if ! [[ "${inplace}" ]]; then
        pushd "${APP_REAL_INSTALL_DIR}"
        tar -cf "${APP_IN_CONTAINER_PATH}"/"${TAG}${VERSION_TAG}.tar" "${BUILD_DIR_NAME}"
        popd
    fi

    fix_apps_perms "${PETSC_DIR}"

done

export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}${APP_BUILD_TAG}/${TAG}${VERSION_TAG}${MODULE_SUFFIX}"

exit

if [[ "${FD_INSTALL_DRY_RUN}" ]]; then
    mkdir -p "${BUILD_STAGE_DIR}/${APP_NAME}${APP_BUILD_TAG}"
    cp "${APP_NAME}.tar" "${BUILD_STAGE_DIR}/${APP_NAME}-${TAG}${VERSION_TAG}.tar"
    export MODULE_FILE="${BUILD_STAGE_DIR}/${APP_NAME}${APP_BUILD_TAG}/${TAG}${VERSION_TAG}${MODULE_SUFFIX}"
    make_modulefiles
    exit 0
fi

make_modulefiles

### 11.) Permissions
fix_apps_perms "${MODULE_FILE%/*}"

### 12.) Anything else?
if [[ $(type -t __petsc_post_build_hook) == function ]]; then
    __petsc_post_build_hook
fi

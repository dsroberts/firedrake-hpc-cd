### All settings used by build scripts
###
### -- Compilers        |   -- Source/destination paths   |   -- Optional settings
###=====================|=================================|=======================================
### MPI_MODULE          |   APPS_PREFIX                   |   VERSION_TAG
### PY_MODULE           |   MODULE_PREFIX                 |   MODULE_SUFFIX
### COMPILER_MODULE     |   SQUASHFS_PATH                 |   MODULE_USE_PATHS
### SINGULARITY_MODULE  |   OVERLAY_BASE                  |   EXTRA_MODULES
### PY_VERSION          |   BUILD_CONTAINER_PATH          |   COMPILER_OPT_FLAGS
### BUILD_NCPUS         |   BUILD_STAGE_DIR               |   PYOP2_COMPILER_OPT_FLAGS
###                     |   EXTRACT_DIR                   |   get_system_specific_petsc_flags()
###                     |   bind_dirs                     |   EXTERNAL_COMMANDS_TO_INCLUDE
export EXTERNAL_COMMANDS_TO_INCLUDE

export MPI_MODULE=cray-mpich/8.1.27
export PY_MODULE=cray-python/3.11.5
export SINGULARITY_MODULE=singularity/4.1.0-nohost

export PRGENV_MODULE="PrgEnv-gnu/8.4.0"

compiler_type=gcc
compiler_version=12.2.0

### Define any compiler-specific things here
if [[ $compiler_type == "gcc" ]]; then
    ### Defer evaluation of this variables until the MKL module is loaded
    export COMPILER_OPT_FLAGS='-O3 -g -march=native -mtune=native'
    export VERSION_TAG="-${compiler_type}${compiler_version%%\.*}"
    export PYOP2_COMPILER_OPT_FLAGS='"-fPIC -O3 -march=native -mtune=native -ffast-math"'

    function get_system_specific_petsc_flags() {
        export SYSTEM_SPECIFIC_FLAGS=("--with-blas-lib=${CRAY_LIBSCI_PREFIX_DIR}/lib/libsci_gnu.so" "--with-lapack-lib=${CRAY_LIBSCI_PREFIX_DIR}/lib/libsci_gnu.so" "--with-scalapack-include=${CRAY_LIBSCI_PREFIX_DIR}/include" "--with-scalapack-lib=${CRAY_LIBSCI_PREFIX_DIR}/lib/libsci_gnu_mpi.so")
    }
fi

export COMPILER_MODULE="${compiler_type}"/"${compiler_version}"
py_ver="${PY_MODULE##*/}"
export PY_VERSION="${py_ver%.*}"

export APPS_PREFIX="/software/projects/pawsey0821/apps"
export MODULE_PREFIX="/software/projects/pawsey0821/modules"
export SQUASHFS_PATH="/tmp/squashfs-root/opt"
export OVERLAY_BASE="/tmp/overlay"
export MODULE_SUFFIX=".lua"
### N.B. CONTAINER_PATH is set by petsc module, so we need a different
### variable inside the build scripts as some of them load & unload
### a petsc module.
export BUILD_CONTAINER_PATH="${APPS_PREFIX}/petsc/etc"
export BUILD_STAGE_DIR="/scratch/pawsey0821/droberts/staging"
export EXTRACT_DIR="/tmp"

export MPICH_CC="gcc"
export MPICH_CXX="g++"
export MPICH_FC="gfortran"
export MPIRUN="/software/projects/pawsey0821/apps/mpich/3.4a2/bin/mpirun"
export HYDRA_LAUNCHER="fork"

export BUILD_NCPUS="${SLURM_NPROCS}"

### Otherwise cmake can't find MPI when building libsupermesh via. pip
export CMAKE_ARGS='-DCMAKE_C_COMPILER=mpicc -DCMAKE_CXX_COMPILER=mpicxx -DCMAKE_Fortran_COMPILER=mpif90 -DCMAKE_Fortran_FLAGS=-fallow-argument-mismatch'
### System ninja install is too old for Fortran
export CMAKE_GENERATOR='Unix Makefiles'

### Limited bits from pawseyenv module to get packages found
export LMOD_PACKAGE_PATH="/software/setonix/lmod-extras"
export LMOD_CUSTOM_COMPILER_GNU_8_0_PREFIX="/software/setonix/2024.05/modules/zen3/${COMPILER_MODULE}/utilities"
export MYSOFTWARE="/software/projects/${PAWSEY_PROJECT}/${USER}"
declare -a MODULE_USE_PATHS=("/software/projects/pawsey0821/modules" "/software/setonix/2024.05/pawsey/modules")
export MODULE_USE_PATHS

### Need compiler module loaded ahead of time to resolve cmake and autoconf
declare -a EXTRA_MODULES=("${PRGENV_MODULE}" "${COMPILER_MODULE}" "cmake/3.27.7" "autoconf/2.69" "libfabric/1.15.2.0")
export EXTRA_MODULES

declare -a EXTERNAL_COMMANDS_TO_INCLUDE=( "make" )
export EXTERNAL_COMMANDS_TO_INCLUDE

declare -a bind_dirs=("/opt/admin-pe" "/opt/AMD" "/opt/amdgpu" "/opt/cray" "/opt/modulefiles" "/opt/pawsey" "/bin" "/boot" "/etc" "/lib" "/lib64" "/local" "/pe" "/ram" "/rootfs.rw" "/root_ro" "/run" "/scratch" "/usr" "/sys/fs/cgroup" "/var/lib/sss" "/var/run/munge" "/var/lib/ca-certificates")

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
###                     |   bind_dirs                     |

export MPI_MODULE=openmpi/4.0.7
### Must have numpy - no reason not to use NCI-provided modules
export PY_MODULE=python3/3.11.7
export SINGULARITY_MODULE=singularity

compiler_type=intel-compiler-llvm
compiler_version=2024.2.0
mkl_version=2024.2.0

### Define any compiler-specific things here
if [[ $compiler_type == "intel-compiler" ]]; then
    export COMPILER_OPT_FLAGS="-O3 -g -xCASCADELAKE"
    export VERSION_TAG="-intelclassic"
    export PYOP2_COMPILER_OPT_FLAGS='"-O3 -fPIC -xHost -fp-model=fast"'

    function get_system_specific_petsc_flags() {
        export SYSTEM_SPECIFIC_FLAGS=( '--with-scalapack-include='${MKLROOT}'/include' '--with-scalapack-lib=-lmkl_scalapack_lp64 -lmkl_intel_lp64 -lmkl_sequential -lmkl_core -lmkl_blacs_openmpi_lp64 -lpthread -lm -ldl' )
    }

elif [[ $compiler_type == "intel-compiler-llvm" ]]; then
    ### Defer evaluation of these variables until the MKL module is loaded - Double quotes must be escaped
    export COMPILER_OPT_FLAGS="-O3 -g -xCASCADELAKE"
    export VERSION_TAG=""
    export PYOP2_COMPILER_OPT_FLAGS='"-O3 -fPIC -xHost -fp-model=fast"'

    function get_system_specific_petsc_flags() {
        export SYSTEM_SPECIFIC_FLAGS=( '--with-scalapack-include='${MKLROOT}'/include' '--with-scalapack-lib=-lmkl_scalapack_lp64 -lmkl_intel_lp64 -lmkl_sequential -lmkl_core -lmkl_blacs_openmpi_lp64 -lpthread -lm -ldl' )
    }

elif [[ $compiler_type == "gcc" ]]; then
    ### Defer evaluation of this variables until the MKL module is loaded
    export COMPILER_OPT_FLAGS="-O3 -g -march=cascadelake -mtune=cascadelake"
    export VERSION_TAG="-${compiler_type}${compiler_version%%\.*}"
    export PYOP2_COMPILER_OPT_FLAGS='"-fPIC -O3 -march=native -mtune=native -ffast-math"'

    function get_system_specific_petsc_flags() {
        export SYSTEM_SPECIFIC_FLAGS="--download-scalapack"
    }
fi

export COMPILER_MODULE="${compiler_type}"/"${compiler_version}"
export MKL_MODULE=intel-mkl/"${mkl_version}"
py_ver="${PY_MODULE##*/}"
export PY_VERSION="${py_ver%.*}"

[[ "${PBS_JOBFS}" ]] && export EXTRACT_DIR="${PBS_JOBFS}" || export EXTRACT_DIR="${TMPDIR}"
export BUILD_NCPUS="${PBS_NCPUS}"
export APPS_PREFIX=/g/data/fp50/apps
export MODULE_PREFIX=/g/data/fp50/modules
export SQUASHFS_PATH="${EXTRACT_DIR}/squashfs-root/opt"
export OVERLAY_BASE="${EXTRACT_DIR}/overlay"
### N.B. CONTAINER_PATH is set by petsc module, so we need a different
### variable inside the build scripts as some of them load & unload
### a petsc module.
export BUILD_CONTAINER_PATH="${APPS_PREFIX}/petsc/etc"
export BUILD_STAGE_DIR=/scratch/fp50/staging
export WRITERS_GROUP=xd2

### Otherwise cmake can't find MPI when building libsupermesh via. pip
export CMAKE_ARGS='-DCMAKE_C_COMPILER=mpicc -DCMAKE_CXX_COMPILER=mpicxx -DCMAKE_Fortran_COMPILER=mpif90'
### System ninja install is too old for Fortran
export CMAKE_GENERATOR='Unix Makefiles'

### pnetcdf will not compile against oneAPI fortran compiler
### with system autoconf - see https://community.intel.com/t5/Intel-Fortran-Compiler/ifx-2021-1-beta04-HPC-Toolkit-build-error-with-loopopt/td-p/1184181
declare -a EXTRA_MODULES=( autoconf/2.72 "${MKL_MODULE}" )
export EXTRA_MODULES

declare -a bind_dirs=("/etc" "/half-root" "/local" "/ram" "/run" "/system" "/usr" "/var/lib/sss" "/var/lib/rpm" "/var/run/munge" "/sys/fs/cgroup" "/iointensive")
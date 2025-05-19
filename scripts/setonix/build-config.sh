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
###                     |                                 |   COMMON_MODULE_EXT

export MPI_MODULE=cray-mpich/8.1.27
export PY_MODULE=python/3.11.6
export SINGULARITY_MODULE=singularity/4.1.0-nohost

compiler_type=gcc
compiler_version=12.2.0
declare -a compiler_support_modules=()

export COMPILER_MODULE="${compiler_type}"/"${compiler_version}"
py_ver="${PY_MODULE##*/}"
export PY_VERSION="${py_ver%.*}"

### Otherwise cmake can't find MPI when building libsupermesh via. pip
export CMAKE_ARGS='-DCMAKE_C_COMPILER=cc -DCMAKE_CXX_COMPILER=CC -DCMAKE_Fortran_COMPILER=ftn'
### System ninja install is too old for Fortran
export CMAKE_GENERATOR='Unix Makefiles'

### Define any compiler-specific things here
if [[ $compiler_type == "gcc" ]]; then
    ### craype-x86-milan module should take care of CPU arch targeting
    export PRGENV_MODULE="PrgEnv-gnu/8.4.0"
    ### Defer evaluation of this variables until the MKL module is loaded
    export COMPILER_OPT_FLAGS='-O3 -g'
    export VERSION_TAG="-${compiler_type}${compiler_version%%\.*}-amdblis"
    export PYOP2_COMPILER_OPT_FLAGS='"-fPIC -O3"'

    function get_system_specific_petsc_flags() {
        ### FFS
        export SYSTEM_SPECIFIC_FLAGS=("--with-blis-lib=/software/setonix/2024.05/software/linux-sles15-zen3/gcc-12.2.0/amdblis-3.0.1-z55ga273wnscwzdylvta3cwzqzatcbhp/lib/libblis-mt.so" "--with-blis-include=/software/setonix/2024.05/software/linux-sles15-zen3/gcc-12.2.0/amdblis-3.0.1-z55ga273wnscwzdylvta3cwzqzatcbhp/include" "--download-scalapack")
    }
    export LMOD_CUSTOM_COMPILER_GNU_8_0_PREFIX="/software/setonix/2024.05/modules/zen3/${COMPILER_MODULE}/utilities:/software/setonix/2024.05/modules/zen3/${COMPILER_MODULE}/libraries:/software/setonix/2024.05/modules/zen3/${COMPILER_MODULE}/programming-languages"
    compiler_support_modules=( "amdblis/3.0.1" "openblas/0.3.24" )
    export CMAKE_ARGS+=' -DCMAKE_Fortran_FLAGS=-fallow-argument-mismatch'
fi

if [[ $compiler_type == "cce" ]]; then
    ### craype-x86-milan module should take care of CPU arch targeting
    export PRGENV_MODULE="PrgEnv-cray/8.4.0"
    ### Defer evaluation of this variables until the MKL module is loaded
    export COMPILER_OPT_FLAGS='-O3 -g'
    export VERSION_TAG="-${compiler_type}${compiler_version%%\.*}"
    export PYOP2_COMPILER_OPT_FLAGS='"-fPIC -O3"'

    function get_system_specific_petsc_flags() {
        ### Why did you rebuild blis with only blis-mt?
        export SYSTEM_SPECIFIC_FLAGS=( "--with-blis-lib=/software/setonix/2024.05/software/linux-sles15-zen3/cce-16.0.1/amdblis-3.0.1-htunr5u3jffjg2hua6rgo527gtz3t45f/lib/libblis-mt.so" "--with-blis-include=/software/setonix/2024.05/software/linux-sles15-zen3/cce-16.0.1/amdblis-3.0.1-htunr5u3jffjg2hua6rgo527gtz3t45f/include" "--download-scalapack" )
    }
    export LMOD_CUSTOM_COMPILER_CRAYCLANG_14_0_PREFIX="/software/setonix/2024.05/modules/zen3/${COMPILER_MODULE}/utilities:/software/setonix/2024.05/modules/zen3/${COMPILER_MODULE}/libraries:/software/setonix/2024.05/modules/zen3/${COMPILER_MODULE}/programming-languages"
    compiler_support_modules=( "amdblis/3.0.1" "openblas/0.3.24" )
fi

if [[ $compiler_type == "aocc" ]]; then
    ### craype-x86-milan module should take care of CPU arch targeting
    export PRGENV_MODULE="PrgEnv-aocc/8.6.0"
    ### Defer evaluation of this variables until the MKL module is loaded
    export COMPILER_OPT_FLAGS='-O3 -g'
    export VERSION_TAG="-${compiler_type}${compiler_version%%\.*}"
    export PYOP2_COMPILER_OPT_FLAGS='"-fPIC -O3"'

    function get_system_specific_petsc_flags() {
        export SYSTEM_SPECIFIC_FLAGS=("--with-blas-lib=${CRAY_PE_LIBSCI_PREFIX_DIR}/lib/libsci_cray.so" "--with-lapack-lib=${CRAY_PE_LIBSCI_PREFIX_DIR}/lib/libsci_cray.so" "--with-scalapack-include=${CRAY_PE_LIBSCI_PREFIX_DIR}/include" "--with-scalapack-lib=${CRAY_PE_LIBSCI_PREFIX_DIR}/lib/libsci_cray_mpi.so")
    }
fi

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

#export MPICH_CC="gcc"
#export MPICH_CXX="g++"
#export MPICH_FC="gfortran"
#export MPIRUN="/software/projects/pawsey0821/apps/mpich/3.4a2/bin/mpirun"
#export HYDRA_LAUNCHER="fork"
export MPICC="cc"
export MPICXX="CC"
export MPIF90="ftn"
export MPIEXEC="srun"

export BUILD_NCPUS="${SLURM_NPROCS}"

### Limited bits from pawseyenv module to get packages found
export LMOD_PACKAGE_PATH="/software/setonix/lmod-extras"
export MYSOFTWARE="/software/projects/${PAWSEY_PROJECT}/${USER}"
declare -a MODULE_USE_PATHS=("${MODULE_PREFIX}" "/software/setonix/2024.05/pawsey/modules")
export MODULE_USE_PATHS

### Need compiler module loaded ahead of time to resolve cmake and autoconf
declare -a EXTRA_MODULES=("${PRGENV_MODULE}" "${COMPILER_MODULE}" "cmake/3.31.6" "libfabric/1.15.2.0" "craype-x86-milan" )
EXTRA_MODULES+=( "${compiler_support_modules[@]}" )
export EXTRA_MODULES

declare -a EXTERNAL_COMMANDS_TO_INCLUDE=( "make" )
export EXTERNAL_COMMANDS_TO_INCLUDE

declare -a bind_dirs=("/opt/admin-pe" "/opt/AMD" "/opt/amdgpu" "/opt/cray" "/opt/modulefiles" "/opt/pawsey" "/bin" "/boot" "/etc" "/lib" "/lib64" "/local" "/pe" "/ram" "/rootfs.rw" "/root_ro" "/run" "/scratch" "/usr" "/sys/fs/cgroup" "/var/lib/sss" "/var/run/munge" "/var/lib/ca-certificates")

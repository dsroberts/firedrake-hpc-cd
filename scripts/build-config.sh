export OMPI_MODULE=openmpi/4.0.7
### Must have numpy - no reason not to use NCI-provided modules
export PY_MODULE=python3/3.11.7

compiler_type=gcc
compiler_version=14.2.0
mkl_version=2024.2.0

### Define any compiler-specific things here
if [[ $compiler_type == "intel-compiler" ]]; then
    export COMPILER_OPT_FLAGS="-O3 -g -xCASCADELAKE"
    export VERSION_TAG="-intelclassic"
    export PYOP2_COMPILER_OPT_FLAGS='"-O3 -fPIC -xHost -fp-model=fast"'

    function get_scalapack_flags() {
        export SCALAPACK_FLAGS='--with-scalapack-include='${MKLROOT}'/include --with-scalapack-lib="-lmkl_scalapack_lp64 -lmkl_intel_lp64 -lmkl_sequential -lmkl_core -lmkl_blacs_openmpi_lp64 -lpthread -lm -ldl"'
    }

elif [[ $compiler_type == "intel-compiler-llvm" ]]; then
    ### Defer evaluation of these variables until the MKL module is loaded - Double quotes must be escaped
    export COMPILER_OPT_FLAGS="-O3 -g -xCASCADELAKE"
    export VERSION_TAG=""
    export PYOP2_COMPILER_OPT_FLAGS='"-O3 -fPIC -xHost -fp-model=fast"'

    function get_scalapack_flags() {
        export SCALAPACK_FLAGS='--with-scalapack-include='${MKLROOT}'/include --with-scalapack-lib="-lmkl_scalapack_lp64 -lmkl_intel_lp64 -lmkl_sequential -lmkl_core -lmkl_blacs_openmpi_lp64 -lpthread -lm -ldl"'
    }

elif [[ $compiler_type == "gcc" ]]; then
    ### Defer evaluation of this variables until the MKL module is loaded
    export COMPILER_OPT_FLAGS="-O3 -g -march=cascadelake -mtune=cascadelake"
    export VERSION_TAG="-${compiler_type}${compiler_version%%\.*}"
    export PYOP2_COMPILER_OPT_FLAGS='"-fPIC -O3 -march=native -mtune=native -ffast-math"'

    function get_scalapack_flags() {
        export SCALAPACK_FLAGS="--download-scalapack"
    }
fi

export COMPILER_MODULE="${compiler_type}"/"${compiler_version}"
export MKL_MODULE=intel-mkl/"${mkl_version}"
py_ver="${PY_MODULE##*/}"
export PY_VERSION="${py_ver%.*}"

export APPS_PREFIX=/g/data/fp50/apps
export MODULE_PREFIX=/g/data/fp50/modules
export SQUASHFS_PATH="${PBS_JOBFS}/squashfs-root/opt"
export OVERLAY_BASE="${PBS_JOBFS}/overlay"
### N.B. CONTAINER_PATH is set by petsc module, so we need a different
### variable inside the build scripts as some of them load & unload
### a petsc module.
export BUILD_CONTAINER_PATH="${APPS_PREFIX}/petsc/etc"

export BUILD_STAGE_DIR=/home/563/dr4292

export WRITERS_GROUP=xd2

declare -a bind_dirs=("/etc" "/half-root" "/local" "/ram" "/run" "/system" "/usr" "/var/lib/sss" "/var/lib/rpm" "/var/run/munge" "/sys/fs/cgroup" "/iointensive")

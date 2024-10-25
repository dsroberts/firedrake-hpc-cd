export OMPI_MODULE=openmpi/4.0.7
### Must have numpy - no reason not to use NCI-provided modules
export PY_MODULE=python3/3.11.7
compiler_version=2024.2.0
mkl_version="${compiler_version}"

export COMPILER_MODULE=intel-compiler-llvm/"${compiler_version}"
export MKL_MODULE=intel-mkl/"${mkl_version}"
py_ver="${PY_MODULE##*/}"
export PY_VERSION="${py_ver%.*}"

export APPS_PREFIX=/g/data/xd2/dr4292/apps
export MODULE_PREFIX=/g/data/xd2/dr4292/apps/Modulefiles
export SQUASHFS_PATH="${PBS_JOBFS}/squashfs-root/opt"
export OVERLAY_BASE="${PBS_JOBFS}/overlay"
### N.B. CONTAINER_PATH is set by petsc module, so we need a different
### variable inside the build scripts as some of them load & unload
### a petsc module.
export BUILD_CONTAINER_PATH="${APPS_PREFIX}/petsc/etc"

export BUILD_STAGE_DIR=/home/563/dr4292

declare -a bind_dirs=( "/etc" "/half-root" "/local" "/ram" "/run" "/system" "/usr" "/var/lib/sss" "/var/lib/rpm" "/var/run/munge" "/sys/fs/cgroup" "/iointensive" )
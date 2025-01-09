### Subject to change
export SINGULARITY_MODULE="singularity/4.1.0-nohost"
export SINGULARITY_BINARY_PATH="/software/setonix/2024.05/software/linux-sles15-zen3/gcc-12.2.0/singularityce-4.1.0-2gadr2xoc2nb4prnnyq2vvztjh6x4wzl/bin/singularity"
export CONTAINER_PATH=${CONTAINER_PATH:-"/software/projects/pawsey0821/apps/petsc/etc/base.sif"}
declare -a bind_dirs=("/opt/admin-pe" "/opt/AMD" "/opt/amdgpu" "/opt/cray" "/opt/modulefiles" "/opt/pawsey" "/bin" "/boot" "/etc" "/lib" "/lib64" "/local" "/pe" "/ram" "rootfs.rw" "root_ro" "/run" "/usr" "/sys/fs/cgroup" "/var/lib/sss" "/var/run/munge" "/var/lib/ca-certificates" "/var/spool/slurmd" "/software" )
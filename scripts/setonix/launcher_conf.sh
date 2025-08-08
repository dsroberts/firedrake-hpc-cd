### Subject to change
export SINGULARITY_MODULE="singularity/4.1.0-nohost"
export SINGULARITY_BINARY_PATH="/software/setonix/2025.08/software/linux-sles15-zen3/gcc-14.2.0/singularityce-4.1.0-oywepmdbs2cm4lhqsz5ipg5gjty6ddc4/bin/singularity"
export CONTAINER_PATH=${CONTAINER_PATH:-"/software/projects/pawsey0821/apps/petsc/etc/base.sif"}
declare -a bind_dirs=("/opt/admin-pe" "/opt/AMD" "/opt/amdgpu" "/opt/cray" "/opt/modulefiles" "/opt/pawsey" "/opt/rocm-6.3.0" "/opt/xpmem" "/bin" "/boot" "/etc" "/lib" "/lib64" "/local" "/pe" "/ram" "/rootfs.rw" "/root_ro" "/run" "/scratch" "/usr" "/sys/fs/cgroup" "/var/lib/sss" "/var/run/munge" "/var/lib/ca-certificates" "/var/spool/slurmd" "/software" )
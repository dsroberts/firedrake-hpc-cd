### Subject to change
export SINGULARITY_BINARY_PATH="/opt/singularity/bin/singularity"
export CONTAINER_PATH=${CONTAINER_PATH:-"/g/data/xd2/dr4292/apps/petsc/etc/base.sif"}
declare -a bind_dirs=( "/etc" "/half-root" "/local" "/ram" "/run" "/system" "/usr" "/var/lib/sss" "/var/run/munge" "/sys/fs/cgroup" "/iointensive" )
function pre_container_launch_hook() {
    unset SINGULARITY_BINDPATH
    copy_dir_to_overlay "${APPS_PREFIX}/./patchelf" "${OVERLAY_EXTERNAL_PATH%/*}/"
    copy_dir_to_overlay "${APPS_PREFIX}/./cmake" "${OVERLAY_EXTERNAL_PATH%/*}/"
    app_path="${OVERLAY_EXTERNAL_PATH%/*}"
    mkdir -p "${app_path%/*}/modules"
    copy_dir_to_overlay "${MODULE_PREFIX}/./patchelf.lua" "${app_path%/*}/modules"
    copy_dir_to_overlay "${MODULE_PREFIX}/./cmake" "${app_path%/*}/modules"
    ln -sf /software-push-aside/setonix "${OVERLAY_BASE}/setonix"
}

function __petsc_pre_container_launch_hook () {
    pre_container_launch_hook
}

function __firedrake_pre_container_launch_hook () {
    pre_container_launch_hook
}

function __petsc_post_build_in_container_hook() {
    resolve_libs "${APP_IN_CONTAINER_PATH}/${TAG}" "${APP_IN_CONTAINER_PATH}/${TAG}"
}

function __firedrake_pre_petsc_version_check() {
    module load "${PRGENV_MODULE}"
}

function __firedrake_post_build_in_container_hook() {
###    b.) Resolve all shared object links
    resolve_libs "${APP_IN_CONTAINER_PATH}/${TAG}" "${APP_IN_CONTAINER_PATH}/${TAG}:${PETSC_DIR}"
}

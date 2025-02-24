#!/usr/bin/env bash
set -e
### Recommended to run on login node.
###
### Yes, 'build' is a stretch, but it is in keeping with the rest
### of the scripts in this repo
###
### Use github action to clone out g-adopt repo, tar it up and
### copy to HPC system
###
module purge

if [[ ${REPO_PATH} ]]; then
    here="${REPO_PATH}/scripts"
    this_script="${here}/build-gadopt.sh"
else
    this_script=$(realpath $0)
    here="${this_script%/*}"
fi
export APP_NAME="g-adopt"
source "${here}/identify-system.sh"

source "${here}/functions.sh"

### Load machine-specific definitions
[[ -e "${here}/${FD_SYSTEM}/build-config.sh" ]] && source "${here}/${FD_SYSTEM}/build-config.sh"
[[ -e "${here}/${FD_SYSTEM}/functions.sh" ]] && source "${here}/${FD_SYSTEM}/functions.sh"

cd "${EXTRACT_DIR}"
if [[ -d "${EXTRACT_DIR}/${APP_NAME}" ]]; then
    rm -rf "${EXTRACT_DIR}/${APP_NAME}"
fi

export APP_BUILD_TAG=""
### Add any/all build type (e.g. 64bit) tags here
if [[ "${DO_64BIT}" ]]; then
    export APP_BUILD_TAG=${APP_BUILD_TAG}"-64bit"
fi

tar -xf "${BUILD_STAGE_DIR}/${APP_NAME}.tar"
pushd "${APP_NAME}"

for p in "${MODULE_USE_PATHS[@]}"; do
    module use ${p}
done
module use "${MODULE_PREFIX}"

for m in "${EXTRA_MODULES[@]}"; do
    module load ${m}
done
module load firedrake"${APP_BUILD_TAG}"
export APP_IN_CONTAINER_PATH="${APPS_PREFIX}/firedrake${APP_BUILD_TAG}"
export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}${APP_BUILD_TAG}${MODULE_SUFFIX}"

pip3 install --target "${APP_IN_CONTAINER_PATH}/gadopt" --upgrade --no-deps .

tar -czf "${APP_IN_CONTAINER_PATH}"/gadopt/demos.tgz demos

copy_and_replace "${here}/../module/${FD_SYSTEM}/${APP_NAME}-base" "${MODULE_FILE}" APP_BUILD_TAG FIREDRAKE_TAG APP_IN_CONTAINER_PATH
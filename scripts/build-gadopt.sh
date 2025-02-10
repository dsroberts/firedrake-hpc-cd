#!/usr/bin/env bash
set -e
### Recommended to run on login node.
###
### Yes, 'build' is a stretch, but it is in keeping with the rest
### of the scripts in this repo
###
### Use github action to clone out g-adopt repo, check out a tag 
### tar it up and copy to HPC system
###
### ==== SECTIONS =====
###
module purge

this_script=$(realpath $0)
here="${this_script%/*}"
export APP_NAME="g-adopt"
source "${here}/identify-system.sh"

source "${here}/functions.sh"

### Load machine-specific definitions
[[ -e "${here}/${FD_SYSTEM}/build-config.sh" ]] && source "${here}/${FD_SYSTEM}/build-config.sh"
[[ -e "${here}/${FD_SYSTEM}/functions.sh" ]] && source "${here}/${FD_SYSTEM}/functions.sh"

cd "${EXTRACT_DIR}"
if [[ ! -d "${EXTRACT_DIR}/${APP_NAME}" ]]; then
    tar -xf "${BUILD_STAGE_DIR}/${APP_NAME}.tar"
fi
pushd "${APP_NAME}"
cd "${EXTRACT_DIR}"
if [[ ! -d "${EXTRACT_DIR}/${APP_NAME}" ]]; then
    tar -xf "${BUILD_STAGE_DIR}/${APP_NAME}.tar"
fi
cd

module use "${MODULE_PREFIX}"
module load firedrake"${APP_BUILD_TAG}"
export APP_IN_CONTAINER_PATH="${APPS_PREFIX}/firedrake${APP_BUILD_TAG}"
export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}${APP_BUILD_TAG}"

pip3 install --target "${APP_IN_CONTAINER_PATH}/gadopt" --upgrade --no-deps .

tar -czf "${APP_IN_CONTAINER_PATH}"/gadopt/demos.tgz demos

copy_and_replace "${here}/../module/${FD_SYSTEM}/${APP_NAME}-base" "${MODULE_FILE}" APP_BUILD_TAG FIREDRAKE_TAG APP_IN_CONTAINER_PATH
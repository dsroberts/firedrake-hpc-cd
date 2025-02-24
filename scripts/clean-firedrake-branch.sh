#!/usr/bin/env bash
module purge

this_script=$(realpath $0)
here="${this_script%/*}"
source "${here}/identify-system.sh"

export MINUSI="-i"
export MINUSCAPITALI="-I"
if [[ "$#" -gt 1 ]]; then
    if [[ "${1}" == "--no-prompt" ]]; then
        export MINUSI=""
        export MINUSCAPITALI=""
    fi
fi

### Load machine-specific definitions
[[ -e "${here}/${FD_SYSTEM}/build-config.sh" ]] && source "${here}/${FD_SYSTEM}/build-config.sh"

if [[ "$#" != 1 ]]; then
    echo "ERROR: Usage: ${0} firedrake/module_to_remove" >&2
    exit 1
fi
export MF="${1}"
if [[ $(grep -c "firedrake.*\/" <<<"${MF}") -eq 0 ]]; then
    echo "ERROR: Module must be a fully qualified module name: ${MF}" >&2
    exit 1
fi

module unuse "${MODULE_PREFIX}"

module_dirname="${MODULE_PREFIX##*/}"
export BRANCH_MODULES="${MODULE_PREFIX/$module_dirname/branch_$module_dirname}"
module use "${BRANCH_MODULES}"

if ! [[ $(module avail -t "${MF}") ]]; then
    echo "ERROR: ${MF} not found in ${BRANCH_MODULES}" >&2
    exit 1
fi

module use "${MODULE_PREFIX}"
module load "${MF}"
export FDB="${FIREDRAKE_BASE}"
export FDT="${FIREDRAKE_TAG}"
module unload "${MF}"

echo " ====== WARNING: about to run: ======"
echo "rm ${FDB}/firedrake-${FDT}.sqsh"
echo "rm ${FDB}/${FDT}"
echo "rm ${BRANCH_MODULES}/${MF}"
echo "rm -r ${FDB}-scripts/${FDT}"
echo " ===================================="

rm "${MINUSI}" "${FDB}/firedrake-${FDT}.sqsh"
rm "${MINUSI}" "${FDB}/${FDT}"
rm "${MINUSI}" "${BRANCH_MODULES}/${MF}"
rm "${MINUSCAPITALI}" -r "${FDB}-scripts/${FDT}"

### Remove matching entries from .modulerc
sed -i '\:'${MF}':d' ${BRANCH_MODULES}/${MF%/*}/.modulerc*

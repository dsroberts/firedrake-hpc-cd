function copy_and_replace() {
    ### Copies the file in $1 to the location in $2 and replaces any occurrence
    ### of __${3}__, __${4}__... with the contents of those environment variables
    in="${1}"
    out="${2}"
    shift 2
    sedstr=''
    for arg in "$@"; do
        sedstr="${sedstr}s:__${arg}__:${!arg}:g;"
    done

    if [[ "${sedstr}" ]]; then
        sed "${sedstr}" <"${in}" >"${out}"
    else
        cp "${in}" "${out}"
    fi

}

function copy_squash_to_overlay() {

    squash="${1}"
    dir="${2}"
    target="${3}"
    pushd "${EXTRACT_DIR}"

    [[ -e "${target}" ]] && rm -rf "${target}"
    mkdir -p "${target%/*}"
    unsquashfs -processors 1 "${squash}"
    mv "${dir}" "${target}"
    rm -rf squashfs-root

    popd
}

function copy_dir_to_overlay() {

    dir="${1}"
    target="${2}"

    mkdir -p "${target%/*}"
    rsync --archive --verbose --partial --progress --one-file-system --itemize-changes --hard-links --acls --relative "${dir}" "${target}"
}

### Basic perms function - overwrite
function fix_apps_perms() {
    for dir in "$@"; do
        chmod -R g=u-w "${dir}"
    done
}

function resolve_libs() {

    libs_path="${1}"
    search_paths="${2}"

    if [[ "${LD_LIBRARY_PATH}" ]]; then
        extra_rpath="${LD_LIBRARY_PATH}:"
    fi
    if [[ "${CRAY_LD_LIBRARY_PATH}" ]]; then
        extra_rpath="${extra_rpath}${CRAY_LD_LIBRARY_PATH}:"
    fi
    extra_rpath="${extra_rpath::-1}"
    declare -a shobjs=()
    declare -a missing_lib_names=()
    
    echo "${extra_rpath}"

    pushd "${libs_path}"

    while read -r -d $'\0' i; do
        header=$( xxd -l17 -p "${i}" )
        ### This is the official Right Way (TM) of determining whether a file is an ELF shared library
        ### first four bytes == 0x7fELF and 16th byte is 3 or maybe 4
        ### https://gist.github.com/x0nu11byt3/bcb35c3de461e5fb66173071a2379779
        if [[ ${header::8} == "7f454c46" ]] && [[ $(( 10#${header:32} )) -ge 3 ]]; then
    	    shobjs+=( "${i}" )
    	    while read lib crap; do 
    	        missing_lib_names+=( "${lib}" )
            done < <( ldd "${i}" | grep found )
        fi
    done < <( find -type f -print0 )

    declare -a sorted_missing=( $( for i in "${missing_lib_names[@]}"; do echo $i; done | sort -u ) )
    for lib in "${sorted_missing[@]}"; do
        while IFS=: read -ra items; do 
            fn=$( find "${items[@]}" -name $lib -print -quit )
            [[ :"${extra_rpath}": =~ :"${fn%/*}": ]] || extra_rpath="${fn%/*}:${extra_rpath}"
        done <<<"${search_paths}"
    done

    module_restore=$( mktemp -u XXXXXXXX )
    module save "${module_restore}"
    module purge
    module load patchelf

    for i in "${shobjs[@]}"; do 
        if [[ $( ldd "${i}" | grep -c found ) -gt 0 ]]; then
            rpath=$( patchelf --print-rpath ${i} )
            patchelf --remove-rpath "${i}"
            patchelf --force-rpath --set-rpath "${rpath}":"${extra_rpath}" "${i}"
            patchelf --force-rpath --shrink-rpath "${i}"
        fi
    done

    module unload patchelf
    module restore "${module_restore}"
    rm -f ~/.lmod.d/"${module_restore}" ~/.config/lmod/"${module_restore}" ~/.module/"${module_restore}"
    popd

}

function make_modulefiles() {

    mkdir -p "${MODULE_FILE%/*}"
    ### A system must provide an APP_NAME-base module file - everything else is optional - module file must already have ${MODULE_SUFFIX} baked in.
    copy_and_replace "${here}/../module/${FD_SYSTEM}/${APP_NAME}-base" "${MODULE_FILE}" APP_IN_CONTAINER_PATH COMPILER_MODULE SINGULARITY_MODULE MPI_MODULE TAG VERSION_TAG PYOP2_COMPILER_OPT_FLAGS PETSC_MODULE
    if [[ "${DO_DEFAULT_MODULE}" ]]; then
        if [[ "${MODULE_SUFFIX}" == .lua ]]; then
            sed -i '/default/d' "${MODULE_FILE%/*}/.modulerc.lua"
            echo "module_version(\"${APP_NAME}${APP_BUILD_TAG}/${TAG}${VERSION_TAG}\",\"default\")" >> "${MODULE_FILE%/*}/.modulerc.lua"
        else
            copy_and_replace "${here}/../module/${FD_SYSTEM}/version-base" "${MODULE_FILE%/*}/.version" TAG
        fi
    fi
    [[ -z "${COMMON_MODULE_EXT}" ]] && export COMMON_MODULE_EXT="common"
    [[ -e "${here}/../module/${FD_SYSTEM}/${APP_NAME}-${COMMON_MODULE_EXT}" ]] && cp "${here}/../module/${FD_SYSTEM}/${APP_NAME}-${COMMON_MODULE_EXT}" "${MODULE_FILE%/*}"

    if [[ "${MODULE_SUFFIX}" == .lua ]]; then
        if [[ "${VERSION_TAG}" ]]; then
            echo "module_version(\"${APP_NAME}${APP_BUILD_TAG}/${TAG}${VERSION_TAG}\",\"${VERSION_TAG:1}\")" >>"${MODULE_FILE%/*}/.modulerc.lua"
        fi
    else
        if [[ ! -e "${MODULE_FILE%/*}"/.modulerc ]]; then
            echo '#%Module1.0' >"${MODULE_FILE%/*}/.modulerc"
            echo '' >>"${MODULE_FILE%/*}/.modulerc"
        fi
        if [[ "${VERSION_TAG}" ]]; then
            echo module-version "${APP_NAME}${APP_BUILD_TAG}/${TAG}${VERSION_TAG}" "${VERSION_TAG:1}" >>"${MODULE_FILE%/*}/.modulerc"
        fi
    fi

}

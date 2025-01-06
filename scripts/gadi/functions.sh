function resolve_libs() {

    libs_path="${1}"
    search_paths="${2}"

    extra_rpath="${LD_LIBRARY_PATH}"
    declare -a shobjs=()
    declare -a missing_lib_names=()
    
    pushd ${libs_path}

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
            [[ :${extra_rpath}: =~ :${fn%/*}: ]] || extra_rpath=${fn%/*}:${extra_rpath}
        done <<<$search_paths
    done

    module_restore=$( mktemp -u )
    module save ${module_restore}
    module purge
    module load patchelf

    for i in "${shobjs[@]}"; do 
        if [[ $( ldd "${i}" | grep -c found ) -gt 0 ]]; then
            rpath=$( patchelf --print-rpath ${i} )
            patchelf --remove-rpath "${i}"
            patchelf --force-rpath --set-rpath "${rpath}":"${extra_rpath}" "${i}"
            patchelf --shrink-rpath "${i}"
        fi
    done

    module unload patchelf
    module restore ${module_restore}
    popd

}

function fix_apps_perms() {
    for dir in "$@"; do
        setfacl -R -b "${dir}"
        chmod -R g=u-w "${dir}"
        setfacl -R -m g::rX,g:${WRITERS_GROUP}:rwX,d:g::rX,d:g:${WRITERS_GROUP}:rwX "${dir}"
    done
}

function __petsc_post_build_in_container_hook() {
    resolve_libs "${APP_IN_CONTAINER_PATH}/${TAG}" "${APP_IN_CONTAINER_PATH}/${TAG}"
}

function copy_and_replace() {
    ### Copies the file in $1 to the location in $2 and replaces any occurence
    ### of __${3}__, __${4}__... with the contents of those environment variables
    in="${1}"
    out="${2}"
    shift 2
    sedstr=''
    for arg in "$@"; do
        sedstr="${sedstr}s:__${arg}__:${!arg}:g;"
    done
    
    if [[ "${sedstr}" ]]; then
        sed "${sedstr}" < "${in}" > "${out}"
    else
        cp "${in}" "${out}"
    fi

}

function prep_overlay() {

    squash="${1}"
    dir="${2}"
    target="${3}"
    pushd "${PBS_JOBFS}"

    mkdir -p "${target%/*}"
    unsquashfs -processors 1 "${squash}"
    mv "${dir}" "${target}"
    rm -rf squashfs-root

    popd
}

### Basic perms function - overwrite
function fix_apps_perms() {
    for dir in "$@"; do
        chmod -R g=u-w "${dir}"
    done
}
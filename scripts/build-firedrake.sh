#!/usr/bin/env bash
set -eu
### Recommended PBS job
### qsub -I -lncpus=1,mem=16GB,walltime=1:00:00,jobfs=100GB,storage=gdata/xd2+scratch/xd2+gdata/fp50 -q copyq
###
### Use github action to checkout out firedrake repo, tar it up and
### copy to gadi
###
### ==== SECTIONS =====
###
### 1.) Intialisation
this_script=$( realpath $0 )
here="${this_script%/*}"
an="${this_script##*/}"
an="${an#*-}"
export APP_NAME="${an%.*}"
source "${here}/build-config.sh"
source "${here}/functions.sh"

### 2.) Extract repo and gather commit/tag data
cd "${PBS_JOBFS}"
if [[ ! -d "${PBS_JOBFS}/${APP_NAME}" ]]; then
    tar -xf "${BUILD_STAGE_DIR}/${APP_NAME}.tar"
fi
pushd "${APP_NAME}"
#export TAG=$( date +%Y%m%d )
### Tag with date of commit
export TAG=$( git show --no-patch --format=%cd --date=format:%Y%m%d )
### matches short commit length on github
export GIT_COMMIT=$( git rev-parse --short=7 HEAD )
export REPO_TAGS=( $( git tag --points-at HEAD ) )
popd

export APP_BUILD_TAG=""
### Add any/all build type (e.g. 64bit) tags here
if [[ "${DO_64BIT}" ]]; then
    export APP_BUILD_TAG=${APP_BUILD_TAG}"-64bit"
fi

export APP_IN_CONTAINER_PATH="${APPS_PREFIX}/${APP_NAME}${APP_BUILD_TAG}"
export OVERLAY_EXTERNAL_PATH="${APP_IN_CONTAINER_PATH//\/g/"${OVERLAY_BASE}"}"
export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}${APP_BUILD_TAG}/${TAG}"
export SQUASHFS_APP_DIR="${APP_NAME}${APP_BUILD_TAG}-${TAG}"

### 3.) Load dependent modules
### This path will not exist inside of the container
if [[ -d "${MODULE_PREFIX}" ]]; then
    module use "${MODULE_PREFIX}"
    module load petsc${APP_BUILD_TAG}
    ### Get petsc module name
    export PETSC_MODULE=$( module list -t | grep petsc )
    export PETSC_TAG="${PETSC_MODULE#*/}"
    module unload petsc${APP_BUILD_TAG}
fi

### 4.) Define 'inner' function(s)
function inner1() {

    ### i1.) Load modules & set environment
    module load cmake/3.24.2
    ### pnetcdf will not compile against oneAPI fortran compiler
    ### with system autoconf - see https://community.intel.com/t5/Intel-Fortran-Compiler/ifx-2021-1-beta04-HPC-Toolkit-build-error-with-loopopt/td-p/1184181
    module load autoconf/2.72

    module load "${COMPILER_MODULE}"
    module load "${MKL_MODULE}"
    module load "${OMPI_MODULE}"
    module load "${PY_MODULE}"

    if [[ "${DO_64BIT}" ]]; then
        export OPTS_64BIT="--petsc-int-type int64"
    else
        export OPTS_64BIT=""
    fi

    export PETSC_DIR="${APPS_PREFIX}/petsc${APP_BUILD_TAG}/${PETSC_TAG}"
    export PETSC_ARCH=default

    export PYOP2_CACHE_DIR=/tmp/pyop2
    export FIREDRAKE_TSFC_KERNEL_CACHE_DIR=/tmp/tsfc
    export XDG_CACHE_HOME=/tmp/xdg
    export FIREDRAKE_CI_TESTS=1

    ### i2.) Install
    cd "${APP_IN_CONTAINER_PATH}/${TAG}"
    python${PY_VERSION} firedrake/scripts/firedrake-install --honour-petsc-dir --mpiexec=mpirun --mpicc=mpicc --mpicxx=mpicxx --mpif90=mpif90 --no-package-manager ${OPTS_64BIT} --venv-name venv
    source "${APP_IN_CONTAINER_PATH}/${TAG}/venv/bin/activate"
    pip3 install jupyterlab assess gmsh imageio jupytext openpyxl pandas pyvista[all] shapely pyroltrilinos siphash24 jupyterview xarray trame_jupyter_extension pygplates
    
    ### i3.) Installation repair
    ###    a.) Link in entire python3 build - <Firedrake specific>
    ln -s "${PYTHON3_BASE}/lib/libpython3.so" venv/lib
    ln -s "${PYTHON3_BASE}/lib/libpython${PY_VERSION}.so" venv/lib
    ln -s "${PYTHON3_BASE}/lib/libpython${PY_VERSION}.so.1.0" venv/lib
    for i in "${PYTHON3_BASE}/lib/python${PY_VERSION}"/*; do 
        [[ ! -e "venv/lib/python${PY_VERSION}/${i##*/}" ]] && ln -s "${i}" "venv/lib/python${PY_VERSION}/${i##*/}"
    done
    for i in "${PYTHON3_BASE}/include/python${PY_VERSION}"/*; do
        [[ ! -e "venv/include/python${PY_VERSION}/${i##*/}" ]] && ln -s "${i}" "venv/include/python${PY_VERSION}/${i##*/}"
    done

    ###    b.) Resolve all shared object links
    resolve_libs "${APP_IN_CONTAINER_PATH}/${TAG}" "${APP_IN_CONTAINER_PATH}/${TAG}:${PETSC_DIR}"

    ###    c.) Fix NCI's broken python installation - <Firedrake specific>
    module load patchelf
    for py in "python${PY_VERSION}" python3 python; do
        patchelf --force-rpath --set-rpath "${APP_IN_CONTAINER_PATH}/${TAG}/venv/lib" "venv/bin/${py}"
    done
    module unload patchelf

    ###    d.) Link in entire OpenMPI build - <Firedrake specific>
    rm venv/bin/mpi{exec,cc,cxx,f90}
    module load "${OMPI_MODULE}"
    for i in $( find "${OPENMPI_BASE}/" ! -type d ); do
        f="${i//$OPENMPI_BASE\//}"
        mkdir -p "venv/${f%/*}"
        ln -sf ${i} "venv/${f}"
    done
    rm -rf venv/lib/{GNU,nvidia} venv/include/{GNU,nvidia}
    mv venv/lib/Intel/* venv/lib
    mv venv/include/Intel/* venv/include
    rmdir venv/{lib,include}/Intel

}

function inner2() {

    source "/opt/${SQUASHFS_APP_DIR}/venv/bin/activate"
    pip3 install --target "${APP_IN_CONTAINER_PATH}/gadopt" --upgrade --no-deps gadopt

}

### 5.) Run inner function(s)
if [[ "$#" -ge 1 ]]; then
    if [[ "${1}" == '--inner' ]]; then
        inner1
        exit 0
    elif [[ "${1}" == '--inner2' ]]; then
        inner2
        exit 0
    fi
fi

### 6.) Pre-existing build check
if [[ -L "${APP_IN_CONTAINER_PATH}/${TAG}" ]]; then
    echo "This version of ${APP_NAME} is already installed - doing nothing"
    exit 0
fi

### 7.) Extract source & dependent squashfs into overlay
prep_overlay "${APPS_PREFIX}/petsc${APP_BUILD_TAG}/petsc-${PETSC_TAG}.sqsh" "${SQUASHFS_PATH}/petsc${APP_BUILD_TAG}-${PETSC_TAG}" "${OVERLAY_EXTERNAL_PATH%/*}/petsc${APP_BUILD_TAG}/${PETSC_TAG}"

mkdir -p "${OVERLAY_EXTERNAL_PATH}/${TAG}"
mv "${APP_NAME}" "${OVERLAY_EXTERNAL_PATH}/${TAG}"

### 8.) Launch container build
bind_str=""
for bind_dir in "${bind_dirs[@]}"; do
    [[ -d "${bind_dir}" ]] && bind_str="${bind_str}${bind_dir},"
done
### Remove trailing comma
bind_str="${bind_str:: -1}"

module load singularity
singularity -s exec --bind "${bind_str},${OVERLAY_BASE}:/g" "${BUILD_CONTAINER_PATH}/base.sif" "${this_script}" --inner

### 9.) Create squashfs
mkdir -p "${SQUASHFS_PATH}"
mv "${OVERLAY_EXTERNAL_PATH}/${TAG}" "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"

wget https://dl.rockylinux.org/pub/rocky/8/AppStream/x86_64/os/Packages/m/mesa-dri-drivers-23.1.4-3.el8_10.x86_64.rpm
rpm2cpio mesa-dri-drivers-23.1.4-3.el8_10.x86_64.rpm | cpio -idmV
mv usr/lib64/dri "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"

wget https://dl.rockylinux.org/pub/rocky/8/AppStream/x86_64/os/Packages/x/xorg-x11-server-Xvfb-1.20.11-24.el8_10.x86_64.rpm
rpm2cpio xorg-x11-server-Xvfb-1.20.11-24.el8_10.x86_64.rpm  | cpio -idmV
mv usr/bin/Xvfb "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}/venv/bin"

mksquashfs squashfs-root "${APP_NAME}.sqsh" -no-fragments -no-duplicates -no-sparse -no-exports -no-recovery -noI -noD -noF -noX -processors 8

### 10.) Create symlinks & modules
mkdir -p "${APP_IN_CONTAINER_PATH}"
ln -s "/opt/${SQUASHFS_APP_DIR}" "${APP_IN_CONTAINER_PATH}/${TAG}"

cp "${APP_NAME}.sqsh" "${APP_IN_CONTAINER_PATH}/${APP_NAME}-${TAG}.sqsh"

mkdir -p "${MODULE_FILE%/*}"
copy_and_replace "${here}/../module/${APP_NAME}-base" "${MODULE_FILE}" APP_IN_CONTAINER_PATH COMPILER_MODULE TAG PETSC_MODULE
copy_and_replace "${here}/../module/version-base" "${MODULE_FILE%/*}/.version" TAG
cp               "${here}/../module/${APP_NAME}-common" "${MODULE_FILE%/*}"

if [[ ! -e "${MODULE_FILE%/*}/.modulerc" ]]; then
    echo '#%Module1.0' > "${MODULE_FILE%/*}/.modulerc"
    echo ''           >> "${MODULE_FILE%/*}/.modulerc"
fi
echo module-version "${APP_NAME}${APP_BUILD_TAG}/${TAG}" "${GIT_COMMIT}" >> "${MODULE_FILE%/*}/.modulerc"
for tag in "${REPO_TAGS[@]}"; do
    echo module-version "${APP_NAME}${APP_BUILD_TAG}/${TAG}" "${tag}" >> "${MODULE_FILE%/*}/.modulerc"
done

mkdir -p "${APP_IN_CONTAINER_PATH}-scripts/${TAG}/overrides"
cp "${here}"/launcher{,_conf}.sh "${APP_IN_CONTAINER_PATH}-scripts/${TAG}"
cp "${here}"/overrides/* "${APP_IN_CONTAINER_PATH}-scripts/${TAG}/overrides"
for i in "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"/venv/bin/*; do
    ln -s launcher.sh "${APP_IN_CONTAINER_PATH}-scripts/${TAG}/${i##*/}"
done

### 11.) Permissions
fix_apps_perms "${MODULE_FILE%/*}" "${APP_IN_CONTAINER_PATH}" "${APP_IN_CONTAINER_PATH}"-scripts

### 12.) Anything else?
singularity -s exec --bind "${bind_str}" --overlay="${APP_IN_CONTAINER_PATH}/${APP_NAME}-${TAG}.sqsh" "${BUILD_CONTAINER_PATH}/base.sif" "${this_script}" --inner2
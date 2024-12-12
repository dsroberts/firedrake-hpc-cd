#!/usr/bin/env ash
### Recommended PBS job
### qsub -I -lncpus=12,mem=48GB,walltime=2:00:00,jobfs=100GB,storage=gdata/xd2+scratch/xd2+gdata/vo05+scratch/vo05...
###
### Use github action to checkout out petsc repo, tar it up and
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
export TAG=0.39

export APP_IN_CONTAINER_PATH="${APPS_PREFIX}/${APP_NAME}"
export OVERLAY_EXTERNAL_PATH="${APP_IN_CONTAINER_PATH//\/g/"${OVERLAY_BASE}"}"
export MODULE_FILE="${MODULE_PREFIX}/${APP_NAME}/${TAG}"
export SQUASHFS_APP_DIR="${APP_NAME}-${TAG}"

declare -a MODULE_USE_PATHS=()

### 3.) Load dependent modules
if [[ -d "${MODULE_PREFIX}" ]]; then
    module use "${MODULE_PREFIX}"
    module load firedrake
    ### Get petsc & firedrake module name
    export PETSC_MODULE=$( module list -t | grep petsc )
    export FIREDRAKE_MODULE=$( module list -t | grep firedrake )
    module unload firedrake
    export PETSC_TAG="${PETSC_MODULE#*/}"
    export FIREDRAKE_TAG="${FIREDRAKE_MODULE#*/}"
    export FIREDRAKE_IN_CONTAINER_PATH="${APPS_PREFIX}/firedrake"
    export PETSC_DIR="${APPS_PREFIX}/petsc/${PETSC_TAG}"
    export PETSC_ARCH=default
fi

### 4.) Define 'inner' function(s)
function inner() {

    ### i1.) Load modules & set environment
    for p in "${MODULE_USE_PATHS[@]}"; do
        module use ${p}
    done

    module load cmake/3.24.2
    ### pnetcdf will not compile against oneAPI fortran compiler
    ### with system autoconf - see https://community.intel.com/t5/Intel-Fortran-Compiler/ifx-2021-1-beta04-HPC-Toolkit-build-error-with-loopopt/td-p/1184181
    module load autoconf/2.72

    module load "${COMPILER_MODULE}"
    module load "${MKL_MODULE}"
    module load "${OMPI_MODULE}"
    module load glew/2.1.0

    source ${FIREDRAKE_IN_CONTAINER_PATH}/${FIREDRAKE_TAG}/venv/bin/activate

    ### i2.) Install
    #wget https://download.osgeo.org/proj/proj-9.3.1.tar.gz
    ### Prepare dependencies on github actions worker
    tar -xzf ~/proj-9.3.1.tar.gz
    pushd proj-9.3.1
    mkdir build
    pushd build
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="${PETSC_DIR}/${PETSC_ARCH}" -DCMAKE_INSTALL_PREFIX=${APP_IN_CONTAINER_PATH}/${TAG} ..
    cmake --build . --parallel "${PBS_NCPUS}"
    cmake --build . --target install
    popd; popd

    #wget https://archives.boost.io/release/1.82.0/source/boost_1_82_0.tar.bz2
    ### Prepare dependencies on github actions worker
    tar -xf ~/boost_1_82_0.tar.bz2
    pushd boost_1_82_0
    ./bootstrap.sh --prefix="${APP_IN_CONTAINER_PATH}/${TAG}" --with-python=$VIRTUAL_ENV/bin/python3
    ### Patch libs/python/src/numpy/dtype.cpp as per github.com/boostorg/python/issues/431
    ./b2 -j$PBS_NCPUS pch=off toolset=intel link=shared address-model=64 architecture=x86 runtime-link=shared
    ./b2 pch=off toolset=intel link=shared address-model=64 architecture=x86 runtime-link=shared install
    popd

    #wget https://github.com/CGAL/cgal/releases/download/v5.6.1/CGAL-5.6.1.tar.xz
    ### Prepare dependencies on github actions worker
    tar -xf ~/CGAL-5.6.1.tar.xz
    pushd CGAL-5.6.1
    mkdir build
    pushd build
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="${PETSC_DIR}/${PETSC_ARCH}:${APP_IN_CONTAINER_PATH}/${TAG}" -DCMAKE_INSTALL_PREFIX=${APP_IN_CONTAINER_PATH}/${TAG} -DCGAL_INSTALL_LIB_DIR=lib -DWITH_CGAL_ImageIO=OFF -DWITH_CGAL_Qt5=OFF  ..
    make install
    popd; popd

    #wget https://github.com/OSGeo/gdal/releases/download/v3.8.2/gdal-3.8.2.tar.gz
    ### Prepare dependencies on github actions worker
    tar -xf ~/gdal-3.8.2.tar.gz
    pushd gdal-3.8.2
    mkdir build
    pushd build
    ### Patch gdal-3.8.2/port/cpl_vsil_libarchive.cpp as per github.com/OSGeo/gdal/pull/10438
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="${PETSC_DIR}/${PETSC_ARCH};${APP_IN_CONTAINER_PATH}/${TAG}" -DCMAKE_INSTALL_PREFIX=${APP_IN_CONTAINER_PATH}/${TAG} ..
    cmake --build . --parallel "${PBS_NCPUS}"
    cmake --build . --target install
    popd; popd

    pushd GPlates
    cp "${here}/../patches/gplates-src-CMakeLists.txt" src
    mkdir build
    pushd build
    cmake -DCMAKE_BUILD_TYPE=Release -DGPLATES_BUILD_GPLATES=FALSE -DGPLATES_INSTALL_STANDALONE=FALSE -DCMAKE_PREFIX_PATH="${PETSC_DIR}/${PETSC_ARCH};${APP_IN_CONTAINER_PATH}/${TAG}" -DCGAL_DIR=${APP_IN_CONTAINER_PATH}/${TAG}/lib/cmake/CGAL -DQWT_INCLUDE_DIR=/usr/include/qt5/qwt ..
    cmake --build . --parallel "${PBS_NCPUS}"
    ### Emulate behaviour of --target install-into-python
    cmake -DCMAKE_INSTALL_PREFIX="${PWD}/src/pygplates" -DBUILD_TYPE=Release -P cmake_install.cmake
    python3 -m pip install --target "${APP_IN_CONTAINER_PATH}/${TAG}/lib/python3.11/site-packages" "${PWD}/src/pygplates"
    popd; popd

    ### i3.) Installation repair
    ###    a.) Resolve all shared object links
    resolve_libs "${APP_IN_CONTAINER_PATH}/${TAG}" "${APP_IN_CONTAINER_PATH}/${TAG}":"${FIREDRAKE_IN_CONTAINER_PATH}/${FIREDRAKE_TAG}":"${PETSC_DIR}/${PETSC_ARCH}"

}

### 5.) Run inner function(s)
if [[ "$#" -ge 1 ]]; then
    if [[ "${1}" == '--inner' ]]; then
        inner
        exit 0
    fi
fi

### 6.) Pre-existing build check
if [[ -L "${APP_IN_CONTAINER_PATH}/${TAG}" ]]; then
    echo "This version of pygplates is already installed - doing nothing"
    exit 0
fi

### 7.) Extract source & dependent squashfs into overlay
prep_overlay "${APPS_PREFIX}/petsc/petsc-${PETSC_TAG}.sqsh" "${SQUASHFS_PATH}/petsc-${PETSC_TAG}" "${OVERLAY_EXTERNAL_PATH%/*}/petsc/${PETSC_TAG}"
prep_overlay "${APPS_PREFIX}/firedrake/firedrake-${FIREDRAKE_TAG}.sqsh" "${SQUASHFS_PATH}/firedrake-${FIREDRAKE_TAG}" "${OVERLAY_EXTERNAL_PATH%/*}/firedrake/${FIREDRAKE_TAG}"

mkdir -p "${OVERLAY_EXTERNAL_PATH}/${TAG}"

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

mksquashfs squashfs-root "${APP_NAME}.sqsh" -no-fragments -no-duplicates -no-sparse -no-exports -no-recovery -noI -noD -noF -noX -processors 8

### 10.) Create symlinks & modules
mkdir -p "${APP_IN_CONTAINER_PATH}"
ln -s "/opt/${SQUASHFS_APP_DIR}" "${APP_IN_CONTAINER_PATH}/${TAG}"

cp "${APP_NAME}.sqsh" "${APP_IN_CONTAINER_PATH}/${APP_NAME}-${TAG}.sqsh"

mkdir -p "${MODULE_FILE%/*}"
copy_and_replace "${here}/../module/${APP_NAME}-base" "${MODULE_FILE}" APP_IN_CONTAINER_PATH TAG FIREDRAKE_TAG PY_VERSION
copy_and_replace "${here}/../module/version-base" "${MODULE_PREFIX}/${APP_NAME}/.version" TAG
cp               "${here}/../module/${APP_NAME}-common" "${MODULE_PREFIX}/${APP_NAME}"

if [[ ! -e "${MODULE_PREFIX}/${APP_NAME}/.modulerc" ]]; then
    echo '#%Module1.0' > "${MODULE_PREFIX}/${APP_NAME}/.modulerc"
    echo ''           >> "${MODULE_PREFIX}/${APP_NAME}/.modulerc"
fi

for tag in "${REPO_TAGS[@]}"; do
    echo module-version "${APP_NAME}/${TAG}" "${tag}" >> "${MODULE_PREFIX}/${APP_NAME}/.modulerc"
done

### 11.) Anything else?

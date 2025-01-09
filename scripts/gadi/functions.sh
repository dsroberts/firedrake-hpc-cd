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

function __firedrake_post_build_in_container_hook() {
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
    for i in $(find "${OPENMPI_BASE}/" ! -type d); do
        f="${i//$OPENMPI_BASE\//}"
        mkdir -p "venv/${f%/*}"
        ln -sf ${i} "venv/${f}"
    done
    rm -rf venv/lib/{GNU,nvidia} venv/include/{GNU,nvidia}
    mv venv/lib/Intel/* venv/lib
    mv venv/include/Intel/* venv/include
    rmdir venv/{lib,include}/Intel
}

function __firedrake_extra_squashfs_contents() {
    wget https://dl.rockylinux.org/pub/rocky/8/AppStream/x86_64/os/Packages/m/mesa-dri-drivers-23.1.4-3.el8_10.x86_64.rpm
    rpm2cpio mesa-dri-drivers-23.1.4-3.el8_10.x86_64.rpm | cpio -idmV
    mv usr/lib64/dri "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}"

    wget https://dl.rockylinux.org/pub/rocky/8/AppStream/x86_64/os/Packages/x/xorg-x11-server-Xvfb-1.20.11-24.el8_10.x86_64.rpm
    rpm2cpio xorg-x11-server-Xvfb-1.20.11-24.el8_10.x86_64.rpm | cpio -idmV
    mv usr/bin/Xvfb "${SQUASHFS_PATH}/${SQUASHFS_APP_DIR}/venv/bin"
}
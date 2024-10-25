### Only do this if DISPLAY isn't set - we probably have a valid Xserver.
if ! [[ "${DISPLAY}" ]]; then
    ### Only mess with driver paths for this process
    for d in {1..99}; do
        [[ -e /tmp/.X{d}-lock ]] || break
    done
    export DISPLAY=:${d}
    export PYVISTA_OFF_SCREEN=true
    export LIBGL_DRIVERS_PATH=/opt/firedrake-"${FIREDRAKE_TAG}"/dri
    export PYVISTA_TRAME_JUPYTER_MODE=extension

    Xvfb :${d} -screen 0 1024x768x24 &
    while [[ ! -S /tmp/.X11-unix/X${d} ]]; do sleep 1; done
fi
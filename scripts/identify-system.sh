#!/usr/bin/env bash
###
### Put whatever you need here to determine what system you're running.
### The install scripts expect the variable FD_SYSTEM to be set in order
### to pick which config files its going to use.

[[ "${FD_SYSTEM}" ]] && return

if [[ $( hostname ) =~ "gadi-" ]]; then
    export FD_SYSTEM="gadi"
elif [[ $( hostname -f ) =~ "setonix.pawsey.org.au" ]]; then
    export FD_SYSTEM="setonix"
fi

if [[ -z "${FD_SYSTEM}" ]]; then
    echo "ERROR! System could not be resolved. Please add an appropriate test to scripts/identify-system.sh" >&2
    exit 1
fi

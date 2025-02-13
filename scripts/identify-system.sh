#!/usr/bin/env bash
###
### Put whatever you need here to determine what system you're running.
### The install scripts expect the variable FD_SYSTEM to be set in order
### to pick which config files its going to use.

[[ "${FD_SYSTEM}" ]] && return

if [[ $( hostname ) =~ "gadi-" ]]; then
    export FD_SYSTEM="gadi"
elif [[ $( grep -c '     ___  ___| |_ ___  _ __ (_)_  __           ,########(,,  ...     ,########/,' /software/pawsey/motd 2>/dev/null ) -gt 0 ]]; then
    ###                 / __|/ _ \ __/ _ \| '_ \| \ \/ /           ,#########,,,,,,,,,,,,,,#######,,
    ###                 \__ \  __/ || (_) | | | | |>  <             ,,,####,,,,,,,,,,,,,,,,,*###,,,
    ###                 |___/\___|\__\___/|_| |_|_/_/\_\             ,,//,,,,,,,,,,,,,,,,,,,,,,,,,
    ###                  The Pawsey Supercomputer System              .,,,,,,,,,,,,,,,,,,,,,,,,,
    export FD_SYSTEM="setonix"
fi

if [[ -z "${FD_SYSTEM}" ]]; then
    echo "ERROR! System could not be resolved. Please add an appropriate test to scripts/identify-system.sh" >&2
    exit 1
fi

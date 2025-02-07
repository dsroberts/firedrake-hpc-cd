# Firedrake HPC CD

Infrastructure for installing [Firedrake](https://github.com/firedrakeproject/firedrake) in several [squashfs](https://en.wikipedia.org/wiki/SquashFS) to be mounted by a Singularity container on HPC systems. The intent is to install firedrake in a way that is user friendly for researchers and performant on large shared filesystems commonly found on HPC systems. To that end, once firedrake is installed onto an HPC system with this method, one only needs to run `module load firedrake` to have a fully functional firedrake distribution ready to go.

## Motivation

Firedrake is intended to run as a package installed into a large python virtual environment. Whilst this is fine on single-user systems with fast SSDs, HPC filesystems tend to prioritise streaming bandwidth and capacity over random access performance. Therefore, a virtual environment containing 45,000+ files that must be scanned through on import often performs quite poorly when installed on HPC filesystems. Furthermore, the requirement for provenance and reproducibility of experiments means that many versions of firedrake may need to be maintained on any given HPC system. Multiple firedrake builds can quickly exceed filesystem quotas imposed by administrators. This system packages core components `petsc` and `firedrake` in separate squashfs filesystems and then uses singularity to mount those filesystems only when needed. This reduces the total file count of a Firedrake installation to under 150, most of which are symlinks to the binaries provided in the python virtual environment. From the perspective of an HPC filesystem, only one file is ever opened for each component, the squashfs.

The installation of each component requires several common steps around creation of the squashfs filesystems, and as such, the the infrastructure is focussed around automated builds. This means that the installation of new Firedrake builds onto HPC systems can be automated by a CI framework, e.g. GitHub Actions.

## System Requirements

These requirements are for the build system. Requirements for Firedrake and Petsc can be found in their respective documentation.

- `bash` >=4.0
- `squashfs-tools`
- `git` >= 1.7.10
- SingularityCE
- Environment Modules/Lmod

There may be additional requirements depending on the system, as some systems may need extra tools or installation steps.

## Installation procedure outline

The `build-*.sh` scripts control installation of components into their respective squashfs, and creation of the supporting modules and launcher scripts on the host system. The scripts first configure the environment and construct the installation directory on a temporary path. This temporary path is then bound to the final installation path on the host when the container is launched. The installation takes place inside the container. On completion, a `squashfs` is created for the final installation and module files are created.

The behaviour on different systems is controlled using a series of hooks within the installation scripts. If the system configuration defines specific function names, those functions will be run at given points during the installation. More information is given below.

Petsc must be installed first, as Firedrake depends on it. 64-bit integer variants can be built by setting the `$DO_64BIT` environment variable before running the build scripts. These builds are automatically tagged with the `-64bit` suffix.

## Porting Guide
To start, create a Singularity container specific to the target system. Any container can be used, however, the entire purpose of the container is to be able to use Singularity to manipulate bind mounting, meaning that it can simply be a series of mount points or symlinks that binds in the entire host operating system. The `.def` file for the container should be placed in the `container/<system>` directory. The scripts expect the container to be located at `$BUILD_CONTAINER_PATH/base.sif` before the build has commenced, where `$BUILD_CONTAINER_PATH` is defined in `scripts/<system>/build-config.sh`.

The `scripts/identify-system.sh` script must be modified such that it can set the `$FD_SYSTEM` variable to a unique identifier based on some property of the system on which it is running. The system should be identified by something that a user is unable to change (i.e. not an environment variable) and something unlikely to be changed throughout the life of the system.

The build scripts expect additional subdirectories in `modules` and `scripts` for the target system. The name of these directories must correspond to the contents of the `$FD_SYSTEM` variable after `scripts/identify-system.sh` has been run.

The minimum set of system-specific files required for an installation on a given system is as follows:
```
firedrake-hpc-cd
├── module
│   └── $FD_SYSTEM
│       ├── firedrake-base
│       └── petsc-base
└── scripts
    └── $FD_SYSTEM
        ├── build-config.sh
        ├── functions.sh
        └── launcher_conf.sh
```

### `build-config.sh`

The build system is configured primarily by environmnet variables, set by the `scripts/$FD_SYSTEM/build-config.sh`. The following environment variables are required by the build system:

#### Compiler Settings
* `MPI_MODULE` - The MPI module to use. If multiple modules are required before loading an MPI module, they must be specified in the optional `EXTRA_MODULES` array variable.
* `PY_MODULE` - The python module to use.
* `COMPILER_MODULE` - The serial C/C++/Fortran compiler module to use
* `SINGULARITY_MODULE` - The singularity module to use
* `PY_VERSION` - The python version in `MAJOR.MINOR` format (e.g. `3.11`)
* `BUILD_NCPUS` - The number of parallel build processes

#### Source/Destination paths
* `APPS_PREFIX` - The top-level directory for all installations
* `MODULE_PREFIX` - The directory where modules will be placed
* `BUILD_CONTAINER_PATH` - Path to the `base.sif` file to be loaded by singularity
* `BUILD_STAGE_DIR` - The path to a directory containing prepared `petsc` and `firedrake` source tar files, named `petsc.tar` and `firedrake.tar` respectively.
* `EXTRACT_DIR` - The temporary path to which the source trees will be extracted. This directory should be placed on temporary storage that will be cleaned up after a batch job as the build scripts do no cleanup by default.
* `SQUASHFS_PATH` - The location on temporary storage that the final build will be placed before the `mksquashfs` command. This path should be relative to `$EXTRACT_DIR`
* `OVERLAY_BASE` - The directory to be bind-mounted into the container over the root directory of `$APPS_PREFIX`. E.g if `APPS_PREFIX=/scratch/project/apps`, `$OVERLAY_BASE:/scratch` will be added to the list of singularity binding flags during the build process. This path should be relative to `$EXTRACT_DIR`
> [!WARNING]  
> The top-level path specified in `$APPS_PREFIX` will not be accessible during the build process. If anything from that file system is required during a build, it must be copied or linked in place using a hook before the build starts. The `build-firedrake.sh` script will automatically copy in the appropriate `petsc` build.
* `bind_dirs` - a bash array of directories that will be bind-mounted in place when singularity is launched. If a directory needs to be mounted on a different path within the container, this must be added in a hook. 

#### Optional settings
* `VERSION_TAG` - A tag to denote that this build of petsc/firedrake is not the default build. Generally used to denote when a non-standard compiler has been used.
* `MODULE_SUFFIX` - The suffix for modules files. `.lua` indicates that the provided `make_modulefiles` function should assume it is working in an Lmod environment. Any other setting (including undefined) implies TCL Environment Modules.
* `MODULE_USE_PATHS` - A bash array of any additional paths on which modules are to be found during the build process. `$MODULE_PATH` is automatically added in `build-firedrake.sh`.
* `EXTRA_MODULES` - A bash array of any additional modules required to be loaded during the build process. The most recent `petsc`module with a matching `$VERSION_TAG` and integer size will be automatically loaded during the firedrake build.
* `COMPILER_OPT_FLAGS` - Compiler flags to add to the petsc build configuration
* `PYOP2_COMPILER_OPT_FLAGS` - Compiler flags to add to PYOP2 kernel builds.
* `get_system_specific_petsc_flags()` - A function that will be run immediately before invoking `python configure.py` for petsc that will allow flags that depend on environment variables set by modules to be resolved. E.g. used for building against vendor BLAS/LAPACK/scalapack libraries. The function must set the `SYSTEM_SPECIFIC_FLAGS` variable.

### `functions.sh`

The `scripts/$FD_SYSTEM/functions.sh` script defines any hooks or function overrides required to complete the build on a given system. All hooks are optional, and this file can be blank, though it is not likely that a generic configuration will be able to build firedrake on any given system. Hooks are functions denoted by a double-underscore followed by the name of the software being built, then a short description of when the hook is run. Current hooks in the build system are:
* `__petsc_post_build_in_container_hook` - A function run immediately after `make` completes for petsc, but before leaving the container environment.
* `__petsc_pre_container_launch_hook` - A function run immediately before `singularity` is launched for the petsc build.
* `__petsc_post_build_hook` - A function run at the very end of the petsc build script after the application has been built and deployed.
* `__firedrake_pre_petsc_version_check` - A function run immediately before attempting to load the petsc module during `build-firedrake.sh` outside of the containerised environment.
* `__firedrake_post_build_in_container_hook` - A function run immediately after firedrake's dependencies are `pip install`'d, but before leaving the container environment.
* `__firedrake_pre_container_launch_hook` - A function run immediately before `singularity` is launched for the firedrake build.
* `__firedrake_extra_squashfs_contents` - A function run after the firedrake build is moved to its final location in `$SQUASHFS_PATH` that adds any additional contents to the environment before the squashfs is created.
* `__firedrake_post_build_hook` - A function run at the very end of the firedrake build script after the application has been built and deployed.

If the existing hooks are not sufficient, additional hooks can be added as necessary at other stages of the build process. Hooks must be gated as follows:
```
if [[ $(type -t __petsc_pre_container_launch_hook) == function ]]; then
    __petsc_pre_container_launch_hook
fi
```
This ensures that no existing builds that do not define the new hook will be affected by it. 

Once installed, the following directory tree under `$APPS_PREFIX` will have been created
```
apps
├── firedrake
│   ├── 20241030 -> /opt/firedrake-20241030
│   ├── firedrake-20241030.sqsh
│   └── gadopt
├── firedrake-scripts
│   └── 20241030
│       ├── activate -> launcher.sh
│       ├── activate.csh -> launcher.sh
|        ...
│       ├── keyring -> launcher.sh
│       ├── launcher_conf.sh
│       ├── launcher.sh
│       ├── loopy -> launcher.sh
|        ...
|       ├── oshrun -> launcher.sh
│       ├── overrides
│       │   └── jupyter.config.sh
│       ├── pcpp -> launcher.sh
|        ...
└── petsc
    ├── 20241009 -> /opt/petsc-20241009
    ├── etc
    └── petsc-20241009.sqsh

```
The `.sqsh` files are the squashfs that contain the complete firedrake and petsc installs. The `20241030` and `20241009` links are named for the date of the git commit corresponding to the respective firedrake and petsc build. Note that they link to `/opt`. In the final stage of the build, the installation is moved from its path in `$APPS_PREFIX` to `/opt` such that the top-level path in `$APPS_PREFIX` remains available when firedrake is run. These symlinks do not resolve outside of the containerised environment, but do resolve when the squashfs is mounted via Singularity. The `firedrake-scripts` directory contains symlinks to the `launcher.sh` script, one for each command present in the firedrake virtual environment `bin` directory. The `launcher.sh` script determines which command was run, then launches singularity with the appropriate bind mounting and overlay flags, then runs that command from inside the containerised environment.

### Modules
A system must proved a `firedrake-base` and `petsc-base` files in `modules/$FD_SYSTEM`. These files are able to use environment variable names as template parameters, which will be replaced with the contents of those environment variables when the module files are created. E.g. The line
```
module load __SINGULARITY_MODULE__ __COMPILER_MODULE__
```
in the module templates becomes
```
module load singularity intel-compiler
```
in the final module files where `$SINGULARITY_MODULE=singularity` and `$COMPILER_MODULE=intel-compiler`. The date of the git commit of the source tree used for the build is used to set the default module version. The 7-character short commit hash is set as an alias, as are any tags present corresponding to that commit at build time. If `$VERSION_TAG` is undefined, the current build will be set to the default version. If `$VERSION_TAG` is defined, all module names and alias versions will be tagged with `$VERSION_TAG`, the current build will be aliased to `firedrake/$VERSION_TAG` or `petsc/$VERSION_TAG`. If `$DO_64BIT` is true, the modules will be named `firedrake-64bit` and `petsc-64bit` respectively.

### `launcher_conf.sh`

This script is run by `launcher.sh` whenever a command from the container is launched. `launcher_conf.sh` does not have access to `build-config.sh` and must contain the following configuration settings:
* `SINGULARITY_BINARY_PATH` - The full path to the singularity binary to use.
* `SINGULARITY_MODULE` - The singularity module to use - only loaded in cases where `$SINGULARITY_BINARY_PATH` is not defined on entry to the script.
* `CONTAINER_PATH` - Full path to the base container used to by singularity. This variable is recommended to be able to be overridden by using the following bash syntax:
```
export CONTAINER_PATH=${CONTAINER_PATH:-/path/to/base.sif}
```
* `bind_dirs` -  - a bash array of directories that will be bind-mounted in place when singularity is launched. This should be the same as `bind_dirs` from `build-config.sh`, except with the top-level path from `$APPS_PREFIX` added to the array entries.

The `launcher.sh` script also contains a hook system that allows the behaviour of different commands to be modified. The script searches the `overrides` subdirectory for files named either `<command>.sh` or `<command>.config.sh` where `<command>` is the name of the symlink used to invoke `launcher.sh`. A script named `<command>.sh` will override the singularity launch behaviour of `launcher.sh` completely, whereas a script named `<command>.config.sh` will be sourced and return control to `launcher.sh`.

### Global `functions.sh`

A set of universal functions is provided in `scripts/functions.sh` that perform actions common to all platforms. If necessary, these functions can be overridden by a function from `scripts/$FD_SYSTEM/functions` script. The functions provided in this script are
* `copy_and_replace` - This function takes an input template and an output file as its first 2 arguments and an arbitrary number of environment variable names beyond that. For each environment variable, it will replace the string `__VARIABLE__` in the template with the contents of `$VARIABLE` in the destination file.
* `copy_squash_to_overlay` - A convenience function that takes a squashfs name as its first argument, a directory within the squashfs as its second argument and a target path for that directory as its third argument. This function extracts the contents of a directory within a squashfs to a destination. Used when building firedrake to ensure the appropriate petsc build is available.
* `copy_dir_to_overlay` - Copy the contents of a directory specified in the first argument to a target specified in the second argument. Used for ensuring the availability of files that would otherwise not be accessible due to a bind mount during the build process.
* `fix_apps_perms` - This function takes an arbitrary number of files or directories as arguments and disables group write permission on all of them. This function should be overridden on a system that supports ACLs.
* `resolve_libs` - This function sets the `DT_RPATH` of all ELF binaries in the directory specified in the first argument to subdirectories of the colon-separated list of directories in the second argument that contain libraries on which those shared objects depend. Running this on an installation removes the need for a module to specify `$LD_LIBRARY_PATH`.
* `make_modulefiles` - This function takes no arguments and creates the module files and aliases and defaults for the current build. If `$MODULE_SUFFIX` is `.lua`, it will use Lmod sematics, otherwise it will use TCL Environment Module semantics. If the `modules/$FD_SYSTEM` directory provides `firedrake-common` or `petsc-common` files, those files will also be copied unaltered to the same directory as the module file.
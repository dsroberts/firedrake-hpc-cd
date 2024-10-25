## Firedrake HPC CD

Infrastructure for installing [Firedrake](https://github.com/firedrakeproject/firedrake) in several squashfs to be mounted by a Singularity container on HPC systems. The intent is to install firedrake in a way that is user friendly for researchers and performant on large shared filesystems commonly found on HPC systems. To that end, once firedrake is installed onto an HPC system with this method, one only needs to run `module load firedrake` to have a fully functional firedrake distribution ready to go.

### Motivation

Firedrake is intended to run as a package installed into a large python virtual environment. Whilst this is fine on single-user systems with fast SSDs, HPC filesystems tend to prioritise streaming bandwidth and capacity over random access performance. Therefore, a virtual environment containing 45,000+ files that must be scanned through on import often performs quite poorly when installed on HPC filesystems. Furthermore, the requirement for provenance and reproducibility of experiments means that many versions of firedrake may need to be maintained on any given HPC system. Multiple firedrake builds can quickly exceed filesystem quotas imposed by administrators. This system packages core components `petsc`, `firedrake` and `pygplates` in separate squashfs filesystems and then uses singularity to mount those filesystems only when needed. This reduces the total file count of a Firedrake installation to under 150, most of which are symlinks to the binaries provided in the python virtual environment. From the perspecive of an HPC filesystem, only one file is ever opened for each component, the squashfs.

The installation of each component requires several common steps around creation of the squashfs filesystems, and as such, the the infrastructure is focussed around automated builds. This means that the installation of new Firedrake builds onto HPC systems can be automated by a CI framework, e.g. GitHub Actions.

### Installation procedure outline

### Launch procedure outline

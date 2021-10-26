# ffmpeg-nvenc-build

* This script will compile and install a static ffmpeg build with [nvenc](https://en.wikipedia.org/wiki/Nvidia_NVENC) support.
* Modify the prefix path and compile options in the script body to suit your needs.
* CUDA , NPP (scale_cuda/scale_npp) included

### Supported OS'es:

* Ubuntu 16.04
* Ubuntu 18.04
* LinuxMint 19.1
* CentOS 7

### Libavformat Patch for Xtream-UI

* I included the patch required for ffmpeg to function with Xtream-UI after compiling.
* patch works for ffmpeg 4.3.1. not yet working on 4.4 

### Based on:

* https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu
* https://gist.github.com/Brainiarc7/3f7695ac2a0905b05c5b

Enjoy! :-)

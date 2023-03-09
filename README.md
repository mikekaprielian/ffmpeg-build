# ffmpeg-nvenc-build

* This script will compile and install a static ffmpeg build with [nvenc](https://en.wikipedia.org/wiki/Nvidia_NVENC) support.
* Modify the prefix path and compile options in the script body to suit your needs.
* CUDA , NPP (scale_cuda/scale_npp) included
* QSV included
* VAAPI included

CUDA and VAAPI doesn't come with static build so you would need to install the Nvidia CUDA and libav-dev packages. 

### Supported OS'es:

* Ubuntu 16.04
* Ubuntu 18.04
* LinuxMint 19.1
* CentOS 7

### segment.c Patch for Xtream-UI

* I included the patch required for ffmpeg to function with Xtream-UI after compiling and updating to the lastest version.
* patch available for ffmpeg 4.3.1/4.3.2
* patch available for ffmpeg 4.4
* patch available for ffmpeg 5.0
* patch available for ffmpeg 5.1

### Based on:

* https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu
* https://gist.github.com/Brainiarc7/3f7695ac2a0905b05c5b

Enjoy! :-)

### If ffmpeg keeps saying packages not found while trying to compile use the following commands. This needs to be done everytime you restart your computer:

 * export PATH="/usr/local/cuda/bin:/root/ffmpeg-build-static-binaries:$PATH"
 * export PKG_CONFIG_PATH="/root/ffmpeg-build-static-binaries/lib/pkgconfig"


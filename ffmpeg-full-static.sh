#!/bin/sh -e

#This script will compile and install a static ffmpeg build with support for nvenc un ubuntu.
#See the prefix path and compile options if edits are needed to suit your needs.

# Based on:  https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu
# Based on:  https://gist.github.com/Brainiarc7/3f7695ac2a0905b05c5b
# Rewritten here: https://github.com/ilyaevseev/ffmpeg-build-static/


# Globals
NASM_VERSION="2.15.03"
YASM_VERSION="1.3.0"
LAME_VERSION="3.100"
OPUS_VERSION="1.3.1"
LASS_VERSION="0.15.2"
CUDA_VERSION="10.1.243-1"
CUDA_RPM_VER="-10-1"
CUDA_REPO_KEY="http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub"
CUDA_DIR="/usr/local/cuda"
WORK_DIR="$HOME/ffmpeg-build-static-sources"
DEST_DIR="$HOME/ffmpeg-build-static-binaries"
TARGET_DIR_SED=$(echo $WORK_DIR | awk '{gsub(/\//, "\\/"); print}')


mkdir -p "$WORK_DIR" "$DEST_DIR" "$DEST_DIR/bin"

export PATH="$DEST_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$DEST_DIR"/lib:$LD_LIBRARY_PATH


MYDIR="$(cd "$(dirname "$0")" && pwd)"  #"

####  Routines  ################################################

Wget() { wget -cN "$@"; }

Make() { make -j$(nproc); make "$@"; }

Clone() {
    local DIR="$(basename "$1" .git)"

    cd "$WORK_DIR/"
    test -d "$DIR/.git" || git clone --depth=1 "$@"

    cd "$DIR"
    git pull
}

PKGS="autoconf automake libtool patch make cmake bzip2 unzip wget git mercurial"

installAptLibs() {
    sudo apt-get update
    sudo apt-get -y --force-yes install $PKGS \
      build-essential pkg-config texi2html software-properties-common \
       libgpac-dev libva-dev python-xcbgen xcb-proto \
       zlib1g-dev python-dev liblzma-dev libtool-bin
}

installYumLibs() {
    sudo yum -y install $PKGS freetype-devel gcc gcc-c++ pkgconfig zlib-devel \
      libtheora-devel libvorbis-devel libva-devel cmake3
}

installLibs() {
    echo "Installing prerequisites"
    . /etc/os-release
    case "$ID" in
        ubuntu | linuxmint ) installAptLibs ;;
        * )                  installYumLibs ;;
    esac
}

installCUDASDKdeb() {
    UBUNTU_VERSION="$1"
    local CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VERSION}/x86_64/cuda-repo-ubuntu1804_${CUDA_VERSION}_amd64.deb"
    Wget "$CUDA_REPO_URL"
    sudo dpkg -i "$(basename "$CUDA_REPO_URL")"
    sudo apt-key adv --fetch-keys "$CUDA_REPO_KEY"
    sudo apt-get -y update
    sudo apt-get -y install cuda

    sudo env LC_ALL=C.UTF-8 add-apt-repository -y ppa:graphics-drivers/ppa
    sudo apt-get -y update
    sudo apt-get -y upgrade
}

installCUDASDKyum() {
    rpm -q cuda-repo-rhel7 2>/dev/null ||
       sudo yum install -y "https://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-repo-rhel7-${CUDA_VERSION}.x86_64.rpm"
    sudo yum install -y "cuda${CUDA_RPM_VER}"
}

installCUDASDK() {
    echo "Installing CUDA and the latest driver repositories from repositories"
    cd "$WORK_DIR/"

    . /etc/os-release
    case "$ID-$VERSION_ID" in
        ubuntu-16.04 ) installCUDASDKdeb 1604 ;;
        ubuntu-18.04 ) installCUDASDKdeb 1804 ;;
        linuxmint-19.1)installCUDASDKdeb 1804 ;;
        centos-7     ) installCUDASDKyum ;;
        * ) echo "ERROR: only CentOS 7, Ubuntu 16.04 or 18.04 are supported now."; exit 1;;
    esac
}

installNvidiaSDK() {
    echo "Installing the nVidia NVENC SDK."
    Clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
    make
    make install PREFIX="$DEST_DIR"
    patch --force -d "$DEST_DIR" -p1 < "$MYDIR/dynlink_cuda.h.patch" ||
        echo "..SKIP PATCH, POSSIBLY NOT NEEDED. CONTINUED.."
}

compileNasm() {
    echo "Compiling nasm"
    cd "$WORK_DIR/"
    Wget "http://www.nasm.us/pub/nasm/releasebuilds/$NASM_VERSION/nasm-$NASM_VERSION.tar.gz"
    tar xzvf "nasm-$NASM_VERSION.tar.gz"
    cd "nasm-$NASM_VERSION"
    ./configure --prefix="$DEST_DIR" --bindir="$DEST_DIR/bin"
    Make install distclean
}

compileYasm() {
    echo "Compiling yasm"
    cd "$WORK_DIR/"
    Wget "http://www.tortall.net/projects/yasm/releases/yasm-$YASM_VERSION.tar.gz"
    tar xzvf "yasm-$YASM_VERSION.tar.gz"
    cd "yasm-$YASM_VERSION/"
    ./configure --prefix="$DEST_DIR" --bindir="$DEST_DIR/bin"
    Make install distclean
}

compileLibX264() {
    echo "Compiling libx264"
    cd "$WORK_DIR/"
    Wget https://code.videolan.org/videolan/x264/-/archive/master/x264-master.tar.bz2
    rm -rf x264-*/ || :
    tar xjvf x264-master.tar.bz2
    cd x264-master/
    ./configure --prefix="$DEST_DIR" --bindir="$DEST_DIR/bin" --enable-static --enable-pic
    Make install distclean
}

compileLibX265() {
    if cd "$WORK_DIR/x265/" 2>/dev/null; then
        hg pull
        hg update
    else
        cd "$WORK_DIR/"
        hg clone http://hg.videolan.org/x265
    fi

    cd "$WORK_DIR/x265/build/linux/"
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DSTATIC_LINK_CRT:BOOL=ON -DENABLE_SHARED:bool=off ../../source
    Make install
    sed -i 's/-lgcc_s/-lgcc_eh/g' "$DEST_DIR/lib/pkgconfig/x265.pc"

    # forward declaration should not be used without struct keyword!
    sed -i.orig -e 's,^ *x265_param\* zoneParam,struct x265_param* zoneParam,' "$DEST_DIR/include/x265.h"
}

compileLibAom() {
    echo "Compiling libaom"
    Clone https://aomedia.googlesource.com/aom
    mkdir ../aom_build
    cd ../aom_build
    which cmake3 && PROG=cmake3 || PROG=cmake
    $PROG -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DENABLE_SHARED=off -DENABLE_NASM=on ../aom
    Make install
}

compileLibfdkcc() {
    echo "Compiling libfdk-cc"
    cd "$WORK_DIR/"
    Wget -O fdk-aac.zip https://github.com/mstorsjo/fdk-aac/zipball/master
    unzip -o fdk-aac.zip
    cd mstorsjo-fdk-aac*
    autoreconf -fiv
    ./configure --prefix="$DEST_DIR" --disable-shared
    Make install distclean
}

compileLibMP3Lame() {
    echo "Compiling libmp3lame"
    cd "$WORK_DIR/"
    Wget "http://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
    tar xzvf "lame-$LAME_VERSION.tar.gz"
    cd "lame-$LAME_VERSION"
    ./configure --prefix="$DEST_DIR" --enable-nasm --disable-shared
    Make install distclean
}

compileLibOpus() {
    echo "Compiling libopus"
    cd "$WORK_DIR/"
    Wget "http://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz"
    tar xzvf "opus-$OPUS_VERSION.tar.gz"
    cd "opus-$OPUS_VERSION"
    #./autogen.sh
    ./configure --prefix="$DEST_DIR" --disable-shared
    Make install distclean
}

compileLibVpx() {
    echo "Compiling libvpx"
    Clone https://chromium.googlesource.com/webm/libvpx
    ./configure --prefix="$DEST_DIR" --disable-examples --enable-runtime-cpu-detect --enable-vp9 --enable-vp8 \
    --enable-postproc --enable-vp9-postproc --enable-multi-res-encoding --enable-webm-io --enable-better-hw-compatibility \
    --enable-vp9-highbitdepth --enable-onthefly-bitpacking --enable-realtime-only \
    --cpu=native --as=nasm --disable-docs
    Make install clean
}

compileLibAss() {
    echo "Compiling libass"
    cd "$WORK_DIR/"
    Wget "https://github.com/libass/libass/releases/download/$LASS_VERSION/libass-$LASS_VERSION.tar.xz"
    tar Jxvf "libass-$LASS_VERSION.tar.xz"
    cd "libass-$LASS_VERSION"
    autoreconf -fiv
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install
}

compileOpenSSL() {
    echo "Compiling openSSL"
    cd "$WORK_DIR/"
    Wget "https://www.openssl.org/source/openssl-1.1.1h.tar.gz"
    tar -xvf "openssl-1.1.1h.tar.gz"
    cd "openssl-1.1.1h"
    ./config --prefix="$DEST_DIR" --openssldir="$WORK_DIR"/openssl-1.1.1h --with-zlib-include="$WORK_DIR"/openssl-1.1.1h/include --with-zlib-lib="$WORK_DIR"/openssl-1.1.1h/lib no-shared zlib
    make -j 4
    make install
}

compileHarfbuzz() {
    echo "Compiling harfbuzz"
    cd "$WORK_DIR/"
    Wget "https://www.freedesktop.org/software/harfbuzz/release/harfbuzz-2.6.7.tar.xz"
    tar -xvf "harfbuzz-2.6.7.tar.xz"
    cd harfbuzz-*
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileFribidi() {
    echo "Compiling fribidi"
    cd "$WORK_DIR/"
    Wget "https://github.com/fribidi/fribidi/releases/download/v1.0.11/fribidi-1.0.11.tar.xz"
    tar -xvf "fribidi-1.0.11.tar.xz"
    cd fribidi-*
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static --disable-docs
    make -j 4
    make install

}

compileLibrtmp() {
    echo "Compiling librtmp"
    cd "$WORK_DIR/"
    Wget "https://rtmpdump.mplayerhq.hu/download/rtmpdump-2.2e.tar.gz"
    tar -xvf "rtmpdump-2.2e.tar.gz"
    cd rtmpdump-2.2e
    sed -i "/INC=.*/d" ./Makefile # Remove INC if present from previous run.
    sed -i "s/prefix=.*/prefix=${TARGET_DIR_SED}\nINC=-I\$(prefix)\/include/" ./Makefile
    sed -i "s/SHARED=.*/SHARED=no/" ./Makefile
    make 
    make install

}

compileLibSoxr() {
    echo "Compiling libsoxr"
    cd "$WORK_DIR/"
    Wget "https://cfhcable.dl.sourceforge.net/project/soxr/soxr-0.1.3-Source.tar.xz"
    tar -xvf "soxr-0.1.3-Source.tar.xz"
    cd soxr-*
    PATH="$DEST_DIR/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DBUILD_SHARED_LIBS:bool=off -DWITH_OPENMP:bool=off -DBUILD_TESTS:bool=off
    make -j 4
    make install

}

compileLibvidstab() {
    echo "Compiling libvidstab"
    cd "$WORK_DIR/"
    Wget "https://github.com/georgmartius/vid.stab/archive/v1.1.0.tar.gz"
    tar -xvf "v1.1.0.tar.gz"
    cd vid.stab-*
    sed -i "s/vidstab SHARED/vidstab STATIC/" ./CMakeLists.txt
    PATH="$DEST_DIR/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DBUILD_SHARED_LIBS:bool=off -DWITH_OPENMP:bool=off
    make -j 4
    make install

}

compileOpenJPEG() {
    echo "Compiling OpenJPEG"
    cd "$WORK_DIR/"
    Wget "https://github.com/uclouvain/openjpeg/archive/refs/tags/v2.4.0.tar.gz"
    tar -xvf "v2.4.0.tar.gz"
    cd openjpeg-2.4.0
    mkdir -v build
    cd build
    cmake .. -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DBUILD_SHARED_LIBS:bool=off
    make 
    make install 
}

compileZimg() {
    echo "Compiling Zimg"
    cd "$WORK_DIR/"
    Wget "https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.3.tar.gz"
    tar -xvf "release-3.0.3.tar.gz"
    cd zimg-release-*
    ./autogen.sh
    ./configure --enable-static  --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibwebp() {
    echo "Compiling libwebp"
    cd "$WORK_DIR/"
    Wget "https://github.com/webmproject/libwebp/archive/refs/tags/v1.2.2.tar.gz"
    tar -xvf "v1.2.2.tar.gz"
    cd libwebp*
    ./autogen.sh
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibvorbis() {
    echo "Compiling libvorbis"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/vorbis/releases/download/v1.3.7/libvorbis-1.3.7.tar.gz"
    tar -xvf "libvorbis-1.3.7.tar.gz"
    cd libvorbis-*
   ./autogen.sh
   ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibogg() {
    echo "Compiling libogg"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/ogg/releases/download/v1.3.5/libogg-1.3.5.tar.xz"
    tar -xvf "libogg-1.3.5.tar.xz"
    cd libogg-1.3.5
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibspeex() {
    echo "Compiling libspeex"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/speex/archive/refs/tags/Speex-1.2.0.tar.gz"
    tar -xvf "Speex-1.2.0.tar.gz"
    cd speex-Speex-1.2.0
    ./autogen.sh
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibxml() {
    echo "Compiling Libxml2"
    cd "$WORK_DIR/"
    Wget "ftp://xmlsoft.org/libxml2/libxml2-2.9.12.tar.gz"
    tar -xvf "libxml2-2.9.12.tar.gz"
    cd libxml2-2.9.12
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static --with-history
    make -j 4
    make install

}

compileLibmfx() {
     echo "Compiling Libmfx"
     git clone https://github.com/lu-zero/mfx_dispatch.git
     cd mfx_dispatch
     autoreconf -fiv
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make install
     libtool --finish "$DEST_DIR"/lib
     ldconfig
     apt-get install -y ocl-icd-opencl-dev opencl-headers libva-dev vainfo
}

compileLibdav1d() {
     echo "compiling Libdav1d"
     sudo apt-get -y install python3-pip
     pip3 install --user meson
     git -C dav1d pull 2> /dev/null || git clone --depth 1 https://code.videolan.org/videolan/dav1d.git
     mkdir -p dav1d/build
     cd dav1d/build
     meson setup -Denable_tools=false -Denable_tests=false --default-library=static .. --prefix "$DEST_DIR" --libdir="$DEST_DIR"/lib
     ninja
     ninja install
}

compileLibxvidcore() {
     echo "compiling Libxvidcore"
     Wget "https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz"
     tar -xvf "xvidcore-1.3.7.tar.gz"
     cd xvidcore/build/generic
     sed -i 's/^LN_S=@LN_S@/& -f -v/' platform.inc.in
     ./configure --prefix="$DEST_DIR" --disable-assembly
     make
     make install
     rm "$DEST_DIR"/lib/libxvidcore.so*
}

compileLibopencore() {
     echo "compiling Libopencore armwb armnb"
     Wget "https://versaweb.dl.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.5.tar.gz"
     tar -xvf "opencore-amr-0.1.5.tar.gz"
     cd opencore-amr-0.1.5
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make
     make install
}

compileLibvoamrwb() {
     echo "compiling Libvoamrwb"
     Wget "https://cfhcable.dl.sourceforge.net/project/opencore-amr/vo-amrwbenc/vo-amrwbenc-0.1.3.tar.gz"
     tar -xvf "vo-amrwbenc-0.1.3.tar.gz"
     cd vo-amrwbenc-0.1.3
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make
     make install
}

compileSDL2() {
     echo "compiling SDL2"
     Wget "https://www.libsdl.org/release/SDL2-2.0.14.tar.gz"
     tar -xvf "SDL2-2.0.14.tar.gz"
     cd SDL2-2.0.14
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make
     make install
}

compilelibxcb() {
     echo "compiling LibXCB"
     Wget "https://xcb.freedesktop.org/dist/libxcb-1.13.tar.bz2"
     tar -xvf "libxcb-1.13.tar.bz2"
     cd libxcb-1.13
     sed -i "s/pthread-stubs//" configure
     ./configure $XORG_CONFIG --prefix="$DEST_DIR" --without-doxygen --disable-shared --enable-static
     make
     make install
     libtool --finish "$DEST_DIR"/lib
}

compilelibXv() {
     echo "compiling LibXv"
     Wget "https://www.x.org/releases/individual/lib/libXv-1.0.11.tar.gz"
     tar -xvf "libXv-1.0.11.tar.gz"
     cd libXv-1.0.11
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static --disable-docs
     make
     make install
}

compileFontconfig() {
    echo "compiling Fontconfig"
    Wget "https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.13.94.tar.xz"
    tar -xvf "fontconfig-2.13.94.tar.xz"
    cd fontconfig-2.13.94
    export PKG_CONFIG="pkg-config --static" 
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static --disable-docs 
    make
    make install
    unset PKG_CONFIG
}
compileFreetype() {
     echo "compiling Freetype"
     Wget "https://downloads.sourceforge.net/freetype/freetype-2.11.1.tar.xz"
     tar -xvf "freetype-2.11.1.tar.xz"
     cd freetype-2.11.1
     sed -ri "s:.*(AUX_MODULES.*valid):\1:" modules.cfg
     sed -r "s:.*(#.*SUBPIXEL_RENDERING) .*:\1:" -i include/freetype/config/ftoption.h
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static --enable-freetype-config --without-harfbuzz
     make
     make install
}
compileLibpng() {
     echo "compiling Libpnb"
     Wget "https://downloads.sourceforge.net/libpng/libpng-1.6.37.tar.xz"
     tar -xvf "libpng-1.6.37.tar.xz"
     cd libpng-1.6.37
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make
     make install
}


compileLibtheora() {
    echo "Compiling LibTheora"
    Wget "https://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.xz"
    tar -xvf "libtheora-1.1.1.tar.xz"
    cd libtheora-1.1.1
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make
    make install
}

compileLibogg() {
    echo "Compiling Libogg"
    Wget "https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.xz"
    tar -xvf "libogg-1.3.5.tar.xz"
    cd libogg-1.3.5
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make
    make install
}
    
compileLibvdpau() {
    echo "Compiling Libvdpau"
    Wget "https://people.freedesktop.org/~aplattner/vdpau/libvdpau-1.2.tar.bz2"
    tar -xvf "libvdpau-1.2.tar.bz2"
    cd libvdpau-1.2
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make
    make install
}

compileLibdrm() {
    echo "Compiling Libdrm"
    Wget "https://dri.freedesktop.org/libdrm/libdrm-2.4.109.tar.xz"
    tar -xvf "libdrm-2.4.109.tar.xz"
    cd libdrm-2.4.109
    apt-get -y install libpciaccess-dev 
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make
    make install
}

compilelibzvbi() {
    echo "Compiling Libzvbi"
    wget "https://versaweb.dl.sourceforge.net/project/zapping/zvbi/0.2.35/zvbi-0.2.35.tar.bz2"
    tar -xvf "zvbi-0.2.35.tar.bz2"
    cd zvbi-0.2.35.tar.bz2
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make
    make install
    
}
    
compileffnvcodec() {
    echo "Compiling ffnvcodec"
    wget "https://github.com/FFmpeg/nv-codec-headers/releases/download/n11.1.5.2/nv-codec-headers-11.1.5.0.tar.gz"
    tar -xvf nv-codec-headers-11.1.5.0.tar.gz
    cd nv-codec-headers
    sed -i 's/\/usr\/local/\/root\/ffmpeg-build-static-binaries/g' Makefile
    make
    make install
    
}

compileFfmpeg(){
    echo "Compiling ffmpeg"
    Clone https://github.com/FFmpeg/FFmpeg -b master
    patch --force -d "$WORK_DIR" -p1 < "$MYDIR/libavformat-5.1-patch-xtream-ui.patch"

    export PATH="$CUDA_DIR/bin:$PATH"  # ..path to nvcc
    PATH="$DEST_DIR/bin:$PATH" PKG_CONFIG_PATH="$DEST_DIR/lib/pkgconfig:$DEST_DIR/lib64/pkgconfig" \
    ./configure \
      --pkg-config-flags="--static" \
      --prefix="$DEST_DIR" \
      --bindir="$DEST_DIR/bin" \
      --extra-cflags="-I $DEST_DIR/include -I $CUDA_DIR/include/" \
      --extra-ldflags="-L $DEST_DIR/lib -L $CUDA_DIR/lib64/" \
      --extra-libs="-lpthread -lm -lz" \
      --ld=g++ \
      --disable-shared \
      --enable-static \
      --disable-crystalhd \
      --enable-cuda \
      --enable-cuda-nvcc \
      --enable-cuda-llvm \
      --enable-cuvid \
      --enable-pic \
      --enable-fontconfig \
      --enable-frei0r \
      --enable-ffnvcodec \
      --enable-ffplay \
      --enable-openssl \
      --enable-gpl \
      --enable-version3 \
      --enable-vaapi \
      --enable-libnpp \
      --enable-libass \
      --enable-libfdk-aac \
      --enable-libfreetype \
      --enable-libmp3lame \
      --enable-libopus \
      --enable-libtheora \
      --enable-libvorbis \
      --enable-libvpx \
      --enable-libx264 \
      --enable-libx265 \
      --enable-libfribidi \
      --enable-libopenjpeg \
      --enable-libsoxr \
      --enable-libspeex \
      --enable-libvidstab \
      --enable-libwebp \
      --enable-libzimg \
      --enable-libmfx \
      --enable-libxvid \
      --enable-libzvbi \
      --enable-libopencore-amrnb \
      --enable-libopencore-amrwb \
      --enable-libvo-amrwbenc \
      --enable-libXv \
      --enable-nonfree \
      --enable-libaom \
      --enable-nvenc \
      --enable-nvdec
    Make install distclean
    hash -r
}

installLibs
installCUDASDK
installNvidiaSDK

compileNasm
compileYasm
compileLibX264
compileLibX265
compileLibAom
compileLibVpx
compileLibfdkcc
compileLibMP3Lame
compileLibOpus
compileLibAss
compileOpenSSL
compileHarfbuzz
compileFribidi
compileffnvcodec
#compileLibrtmp not working yet (--enable-librtmp cannot be used yet)
compileLibSoxr
compileLibvidstab
compileOpenJPEG
compileZimg
compileLibwebp
compileLibvorbis
compileLibogg
compileLibspeex
compileLibxml
compileLibdav1d
compileLibxvidcore
compileSDL2
compilelibxcb
compilelibXv
compileFontconfig
compileLibtheora
compileFreetype
compileLibpng
compileLibogg
compileLibvdpau
compileFfmpeg

echo "Complete!"

## END ##


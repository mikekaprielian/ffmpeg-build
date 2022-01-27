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
LASS_VERSION="0.14.0"
CUDA_VERSION="10.1.243-1"
CUDA_RPM_VER="-10-1"
CUDA_REPO_KEY="http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub"
CUDA_DIR="/usr/local/cuda"
WORK_DIR="$HOME/ffmpeg-build-static-sources"
DEST_DIR="$HOME/ffmpeg-build-static-binaries"

mkdir -p "$WORK_DIR" "$DEST_DIR" "$DEST_DIR/bin"

export PATH="$DEST_DIR/bin:$PATH"

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
      libfreetype6-dev libgpac-dev libsdl1.2-dev libtheora-dev libva-dev \
      libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev libfribidi-dev libcrystalhd-dev libssl-dev zlib1g-dev
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
    ./configure --prefix="$DEST_DIR" --disable-shared
    Make install distclean
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
    tar -xzf rtmpdump-2.2e.tar.gz
    cd rtmpdump*
    sed -i "/INC=.*/d" ./Makefile # Remove INC if present from previous run.
    sed -i "s/prefix=.*/prefix="$DEST_DIR"\nINC=-I\$(prefix)\/include/" ./Makefile
    sed -i "s/SHARED=.*/SHARED=no/" ./Makefile
    make install_base

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
    Make install distclean
}

compileZimg() {
    echo "Compiling Zimg"
    cd "$WORK_DIR/"
    Wget "https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.3.tar.gz"
    tar -xvf "release-3.0.3.tar.gz"
    cd zimg-release-*
    ./autogen.sh
    ./configure --enable-static  --prefix="$DEST_DIR" --disable-shared
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
    ./configure --prefix="$DEST_DIR" --disable-shared
    make -j 4
    make install

}

compileLibvorbis() {
    echo "Compiling libvorbis"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/vorbis/releases/download/v1.3.7/libvorbis-1.3.7.tar.gz"
    tar -xvf "libvorbis-1.3.7.tar.gz"
    cd libvorbis*
   ./autogen.sh
   ./configure --prefix="$DEST_DIR" --disable-shared
    make -j 4
    make install

}

compileLibogg() {
    echo "Compiling libogg"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/ogg/releases/download/v1.3.5/libogg-1.3.5.tar.xz"
    tar -xvf "libogg-1.3.5.tar.xz"
    cd libogg*
    ./autogen.sh
    ./configure --prefix="$DEST_DIR" --disable-shared
    make -j 4
    make install

}

compileLibspeex() {
    echo "Compiling libspeex"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/speex/archive/refs/tags/Speex-1.2.0.tar.gz"
    tar -xvf "Speex-1.2.0.tar.gz"
    cd Speex-*
    ./autogen.sh
    ./configure --prefix=$TARGET_DIR --disable-shared
    make -j 4
    make install

}

compile Libxml() {

    echo "Compiling Libxml2"
    cd "$WORK_DIR/"
    Wget "ftp://xmlsoft.org/libxml2/libxml2-2.9.2.tar.gz"
    tar -xvf "libxml2-2.9.2.tar.gz"
    ./configure --prefix=/root/ffmpeg_build --enable-static --with-history
    make -j 4
    make install

}

compileFfmpeg(){
    echo "Compiling ffmpeg"
    Clone https://github.com/FFmpeg/FFmpeg -b n4.3.2
    patch --force -d "$WORK_DIR" -p1 < "$MYDIR/libavformat-4.3.1-patch-xtream-ui.patch"

    export PATH="$CUDA_DIR/bin:$PATH"  # ..path to nvcc
    PKG_CONFIG_PATH="$DEST_DIR/lib/pkgconfig:$DEST_DIR/lib64/pkgconfig" \
    ./configure \
      --pkg-config-flags="--static" \
      --prefix="$DEST_DIR" \
      --bindir="$DEST_DIR/bin" \
      --extra-cflags="-I $DEST_DIR/include -I $CUDA_DIR/include/" \
      --extra-ldflags="-L $DEST_DIR/lib -L $CUDA_DIR/lib64/" \
      --extra-libs="-lpthread -lm -lz" \
      --extra-cflags="--static" \
      --disable-shared \
      --enable-cuda \
      --enable-cuda-nvcc \
      --enable-cuda-llvm \
      --enable-cuvid \
      --enable-libnpp \
      --enable-pic \
      --enable-ffplay \
      --enable-ffnvcodec \
      --enable-openssl \
      --enable-gpl \
      --enable-librtmp \
      --enable-vaapi \
      --enable-version3 \
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
# TODO: libogg
# TODO: libvorbis
compileFfmpeg

echo "Complete!"

## END ##

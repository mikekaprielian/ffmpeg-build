#!/bin/sh -e

#This script will compile and install a static ffmpeg build with support for nvenc un ubuntu.
#See the prefix path and compile options if edits are needed to suit your needs.

# Based on:  https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu
# Based on:  https://gist.github.com/Brainiarc7/3f7695ac2a0905b05c5b
# Rewritten here: https://github.com/ilyaevseev/ffmpeg-build-static/


# Globals
NASM_VERSION="2.16"
YASM_VERSION="1.3.0"
AOM_VERSION="v3.5.0"
LAME_VERSION="3.100"
OPUS_VERSION="1.3.1"
LASS_VERSION="0.17.1"
CUDA_VERSION="10.1.243-1"
SSL_VERSION="1.1.1t"
BUZZ_VERSION="2.6.7"
FRIBIDI_VERSION="1.0.12"
RTMP_VERSION="2.3"
SOXR_VERSION="0.1.3"
VIDSTAB_VERSION="v1.1.1"
JPEG_VERSION="v2.5.0"
ZIMG_VERSION="3.0.4"
WEBP_VERSION="v1.3.0"
VORBIS_VERSION="1.3.7"
OGG_VERSION="1.3.5"
SPEEX_VERSION="1.2.1"
XML2_VERSION="2.9.12"
XVID_VERSION="1.3.7"
AMR_VERSION="0.1.6"
AMRWB_VERSION="0.1.3"
SDL2_VERSION="2.26.4"
XCB_VERSION="1.13"
XV_VERSION="1.0.12"
FONTC_VERSION="2.14.2"
FREETYPE_VERSION="2.13.0"
LIBPNG_VERSION="1.6.39"
THEORA_VERSION="1.1.1"
VDPAU_VERSION="1.2"
DRM_VERSION="2.4.100"
ZVBI_VERSION="0.2.35"
FREI0R_VERSION="1.8.0"

CUDA_RPM_VER="-10-1"
CUDA_REPO_KEY="http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub"
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
      build-essential pkg-config texi2html software-properties-common doxygen \
       libgpac-dev libpciaccess-dev python-xcbgen xcb-proto \
       zlib1g-dev python-dev liblzma-dev libtool-bin
}

installYumLibs() {
    sudo yum -y install $PKGS freetype-devel gcc gcc-c++ pkgconfig zlib-devel \
      libtheora-devel libvorbis-devel cmake3
}

installLibs() {
    echo "Installing prerequisites"
    . /etc/os-release
    case "$ID" in
        ubuntu | linuxmint ) installAptLibs ;;
        * )                  installYumLibs ;;
    esac
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

compileFontconfig() {
     echo "compiling Fontconfig"
     cd "$WORK_DIR/"
     Wget "https://www.freedesktop.org/software/fontconfig/release/fontconfig-$FONTC_VERSION.tar.xz"
     tar -xvf "fontconfig-$FONTC_VERSION.tar.xz"
     cd fontconfig-$FONTC_VERSION
     export PKG_CONFIG="pkg-config --static" 
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static --disable-docs 
     make
     make install
     unset PKG_CONFIG
}

compileFrei0r() {

     echo "Compiling Frei0r"
     cd "$WORK_DIR/"
     Wget "https://files.dyne.org/frei0r/releases/frei0r-plugins-$FREI0R_VERSION.tar.gz"
     tar -xvf "frei0r-plugins-$FREI0R_VERSION.tar.gz"
     cd frei0r-plugins-$FREI0R_VERSION
     mkdir -vp build
     cd build

     cmake -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DCMAKE_BUILD_TYPE=Release -DWITHOUT_OPENCV=TRUE -DWITHOUT_GAVL=TRUE -Wno-dev ..
     make
     make install
}

compileHarfbuzz() {
    echo "Compiling harfbuzz"
    cd "$WORK_DIR/"
    Wget "https://www.freedesktop.org/software/harfbuzz/release/harfbuzz-$BUZZ_VERSION.tar.xz"
    tar -xvf "harfbuzz-$BUZZ_VERSION.tar.xz"
    cd harfbuzz-*
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibAom() {
    echo "Compiling libaom"
    cd "$WORK_DIR/"
    git clone --branch $AOM_VERSION https://aomedia.googlesource.com/aom
    mkdir aom_build
    cd aom_build
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | sudo apt-key add -
    sudo apt-add-repository 'deb https://apt.kitware.com/ubuntu/ bionic main'
    sudo apt-get update
    sudo apt install -y cmake
    which cmake3 && PROG=cmake3 || PROG=cmake
    $PROG -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DENABLE_SHARED=off -DENABLE_NASM=on ../aom
    make
    make install
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

compileLibdav1d() {
     echo "Compiling Libdav1d"
     cd "$WORK_DIR/"
     sudo apt-get -y install python3-pip
     pip3 install --user meson
     git -C dav1d pull 2> /dev/null || Clone https://code.videolan.org/videolan/dav1d.git
     mkdir -p dav1d/build
     cd dav1d/build
     meson setup -Denable_tools=false -Denable_tests=false --default-library=static .. --prefix "$DEST_DIR" --libdir="$DEST_DIR"/lib
     ninja
     ninja install
}

compileLibdrm() {
     echo "Compiling Libdrm"
     cd "$WORK_DIR/"
     Wget "https://dri.freedesktop.org/libdrm/libdrm-$DRM_VERSION.tar.gz"
     tar -xvf "libdrm-$DRM_VERSION.tar.gz"
     cd libdrm-$DRM_VERSION
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make
     make install
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

compileLibFreetype() {
     echo "compiling LibFreetype"
     cd "$WORK_DIR/"
     Wget "https://downloads.sourceforge.net/freetype/freetype-$FREETYPE_VERSION.tar.xz"
     tar -xvf "freetype-$FREETYPE_VERSION.tar.xz"
     cd freetype-$FREETYPE_VERSION
     sed -ri "s:.*(AUX_MODULES.*valid):\1:" modules.cfg
     sed -r "s:.*(#.*SUBPIXEL_RENDERING) .*:\1:" -i include/freetype/config/ftoption.h
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static --enable-freetype-config --without-harfbuzz
     make
     make install
}

compileLibFribidi() {
    echo "Compiling Libfribidi"
    cd "$WORK_DIR/"
    Wget "https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz"
    tar -xvf "fribidi-$FRIBIDI_VERSION.tar.xz"
    cd fribidi-*
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static --disable-docs
    make -j 4
    make install

}

compileLibmfx() {
     echo "Compiling Libmfx"
     cd "$WORK_DIR/"
     Clone https://github.com/lu-zero/mfx_dispatch.git
     cd "$WORK_DIR/mfx_dispatch"
     autoreconf -fiv
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make install
     libtool --finish "$DEST_DIR"/lib
     ldconfig
     apt-get install -y ocl-icd-opencl-dev opencl-headers vainfo
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

compileLibogg() {
    echo "Compiling libogg"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/ogg/releases/download/v$OGG_VERSION/libogg-$OGG_VERSION.tar.xz"
    tar -xvf "libogg-$OGG_VERSION.tar.xz"
    cd libogg-$OGG_VERSION
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibopencore() {
     echo "compiling Libopencore armnb"
     cd "$WORK_DIR/"
     Wget "https://versaweb.dl.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-$AMR_VERSION.tar.gz"
     tar -xvf "opencore-amr-$AMR_VERSION.tar.gz"
     cd opencore-amr-$AMR_VERSION
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make
     make install
}

compileLibOpenJPEG() {
    echo "Compiling LibOpenJPEG"
    cd "$WORK_DIR/"
    Wget "https://github.com/uclouvain/openjpeg/archive/refs/tags/$JPEG_VERSION.tar.gz"
    tar -xvf "$JPEG_VERSION.tar.gz"
    cd openjpeg-*
    mkdir -v build
    cd build
    cmake .. -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DBUILD_SHARED_LIBS:bool=off
    make -j 4
    make install 
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

compileLibpng() {
     echo "compiling Libpnb"
     cd "$WORK_DIR/"
     Wget "https://downloads.sourceforge.net/libpng/libpng-$LIBPNG_VERSION.tar.xz"
     tar -xvf "libpng-$LIBPNG_VERSION.tar.xz"
     cd libpng-$LIBPNG_VERSION
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make
     make install
}

compileLibrtmp() {
    echo "Compiling librtmp"
    cd "$WORK_DIR/"
    Clone "https://github.com/mikekaprielian/RTMPDump-OpenSSL-1.1.git"
    cd RTMPDump-OpenSSL-1.1
    make prefix=/root/ffmpeg-build-static-binaries SHARED= 
    make install prefix=/root/ffmpeg-build-static-binaries SHARED=
}

compileLibspeex() {
    echo "Compiling libspeex"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/speex/archive/refs/tags/Speex-$SPEEX_VERSION.tar.gz"
    tar -xvf "Speex-$SPEEX_VERSION.tar.gz"
    cd speex-Speex-$SPEEX_VERSION
    ./autogen.sh
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibSoxr() {
    echo "Compiling libsoxr"
    cd "$WORK_DIR/"
    Wget "https://cfhcable.dl.sourceforge.net/project/soxr/soxr-$SOXR_VERSION-Source.tar.xz"
    tar -xvf "soxr-$SOXR_VERSION-Source.tar.xz"
    cd soxr-*
    PATH="$DEST_DIR/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DBUILD_SHARED_LIBS:bool=off -DWITH_OPENMP:bool=off -DBUILD_TESTS:bool=off
    make -j 4
    make install

}

compileLibtheora() {
    echo "Compiling LibTheora"
    cd "$WORK_DIR/"
    Wget "https://downloads.xiph.org/releases/theora/libtheora-$THEORA_VERSION.tar.xz"
    tar -xvf "libtheora-$THEORA_VERSION.tar.xz"
    sed -i 's/png_sizeof/sizeof/g' examples/png2theora.c
    cd libtheora-$THEORA_VERSION
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make
    make install
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

compileLibVpx() {
    echo "Compiling libvpx"
    cd "$WORK_DIR/"
    Clone https://chromium.googlesource.com/webm/libvpx
    ./configure --prefix="$DEST_DIR" --disable-examples --enable-runtime-cpu-detect --enable-vp9 --enable-vp8 \
    --enable-postproc --enable-vp9-postproc --enable-multi-res-encoding --enable-webm-io --enable-better-hw-compatibility \
    --enable-vp9-highbitdepth --enable-onthefly-bitpacking --enable-realtime-only \
    --cpu=native --as=nasm --disable-docs
    Make install clean
}

compileLibvidstab() {
    echo "Compiling libvidstab"
    cd "$WORK_DIR/"
    Wget "https://github.com/georgmartius/vid.stab/archive/$VIDSTAB_VERSION.tar.gz"
    tar -xvf "$VIDSTAB_VERSION.tar.gz"
    cd vid.stab-*
    sed -i "s/vidstab SHARED/vidstab STATIC/" ./CMakeLists.txt
    PATH="$DEST_DIR/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DBUILD_SHARED_LIBS:bool=off -DWITH_OPENMP:bool=off
    make -j 4
    make install

}

compileLibvoamrwb() {
     echo "compiling Libvoamrwb"
     cd "$WORK_DIR/"
     Wget "https://gigenet.dl.sourceforge.net/project/opencore-amr/vo-amrwbenc/vo-amrwbenc-$AMRWB_VERSION.tar.gz"
     tar -xvf "vo-amrwbenc-$AMRWB_VERSION.tar.gz"
     cd vo-amrwbenc-$AMRWB_VERSION
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make
     make install
}

compileLibvorbis() {
    echo "Compiling libvorbis"
    cd "$WORK_DIR/"
    Wget "https://github.com/xiph/vorbis/releases/download/v$VORBIS_VERSION/libvorbis-$VORBIS_VERSION.tar.gz"
    tar -xvf "libvorbis-$VORBIS_VERSION.tar.gz"
    cd libvorbis-*
   ./autogen.sh
   ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibwebp() {
    echo "Compiling libwebp"
    cd "$WORK_DIR/"
    Wget "https://github.com/webmproject/libwebp/archive/refs/tags/$WEBP_VERSION.tar.gz"
    tar -xvf "$WEBP_VERSION.tar.gz"
    cd libwebp*
    ./autogen.sh
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibxcb() {
     echo "compiling LibXCB"
     cd "$WORK_DIR/"
     Wget "https://xcb.freedesktop.org/dist/libxcb-$XCB_VERSION.tar.bz2"
     tar -xvf "libxcb-$XCB_VERSION.tar.bz2"
     cd libxcb-$XCB_VERSION
     sed -i "s/pthread-stubs//" configure
     ./configure $XORG_CONFIG --prefix="$DEST_DIR" --without-doxygen --disable-shared --enable-static
     make
     make install
     libtool --finish "$DEST_DIR"/lib
}

compileLibxml2() {
    echo "Compiling Libxml2"
    cd "$WORK_DIR/"
    Wget "ftp://xmlsoft.org/libxml2/libxml2-$XML2_VERSION.tar.gz"
    tar -xvf "libxml2-$XML2_VERSION.tar.gz"
    cd libxml2-$XML2_VERSION
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static --with-history
    make -j 4
    make install

}

compileLibXv() {
     echo "compiling LibXv"
     cd "$WORK_DIR/"
     Wget "https://www.x.org/releases/individual/lib/libXv-$XV_VERSION.tar.gz"
     tar -xvf "libXv-$XV_VERSION.tar.gz"
     cd libXv-$XV_VERSION
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static --disable-docs
     make
     make install
}

compileLibvdpau() {
    echo "Compiling Libvdpau"
    cd "$WORK_DIR/"
    Wget "https://people.freedesktop.org/~aplattner/vdpau/libvdpau-$VDPAU_VERSION.tar.bz2"
    tar -xvf "libvdpau-$VDPAU_VERSION.tar.bz2"
    cd libvdpau-$VDPAU_VERSION
    ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
    make
    make install
}

compileLibxvidcore() {
     echo "compiling Libxvidcore"
     cd "$WORK_DIR/"
     Wget "https://downloads.xvid.com/downloads/xvidcore-$XVID_VERSION.tar.gz"
     tar -xvf "xvidcore-$XVID_VERSION.tar.gz"
     cd xvidcore/build/generic
     ./configure --prefix="$DEST_DIR" --enable-static --disable-shared
     make
     make install
     rm "$DEST_DIR"/lib/libxvidcore.so*
}

compileLibzimg() {
    echo "Compiling Libzimg"
    cd "$WORK_DIR/"
    Wget "https://github.com/sekrit-twc/zimg/archive/refs/tags/release-$ZIMG_VERSION.tar.gz"
    tar -xvf "release-$ZIMG_VERSION.tar.gz"
    cd zimg-release-*
    ./autogen.sh
    ./configure --enable-static  --prefix="$DEST_DIR" --disable-shared --enable-static
    make -j 4
    make install

}

compileLibzvbi() {
     echo "Compiling Libzvbi"
     cd "$WORK_DIR/"
     Wget "https://versaweb.dl.sourceforge.net/project/zapping/zvbi/$ZVBI_VERSION/zvbi-$ZVBI_VERSION.tar.bz2"
     tar -xvf "zvbi-$ZVBI_VERSION.tar.bz2"
     cd zvbi-$ZVBI_VERSION
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make
     make install
    
}

compileOpenSSL() {
    echo "Compiling openSSL"
    cd "$WORK_DIR/"
    Wget "https://www.openssl.org/source/openssl-$SSL_VERSION.tar.gz"
    tar -xvf "openssl-$SSL_VERSION.tar.gz"
    cd "openssl-$SSL_VERSION"
    ./config --prefix="$DEST_DIR" --openssldir="$WORK_DIR"/openssl-$SSL_VERSION --with-zlib-include="$WORK_DIR"/openssl-$SSL_VERSION/include --with-zlib-lib="$WORK_DIR"/openssl-1.1.1h/lib no-shared zlib
    make -j 4
    make install
}

compileSDL2() {
     echo "compiling SDL2"
     cd "$WORK_DIR/"
     Wget "https://www.libsdl.org/release/SDL2-$SDL2_VERSION.tar.gz"
     tar -xvf "SDL2-$SDL2_VERSION.tar.gz"
     cd SDL2-$SDL2_VERSION
     ./configure --prefix="$DEST_DIR" --disable-shared --enable-static
     make
     make install
}

compileFfmpeg(){
    echo "Compiling ffmpeg"
    Clone https://github.com/FFmpeg/FFmpeg -b "release/5.1"
    patch --force -d "$WORK_DIR" -p1 < "$MYDIR/libavformat-5.1-patch-xtream-ui.patch"

    export PATH="$PATH"  # ..path to nvcc
    PATH="$DEST_DIR/bin:$PATH" PKG_CONFIG_PATH="$DEST_DIR/lib/pkgconfig:$DEST_DIR/lib64/pkgconfig" \
    ./configure \
      --pkg-config-flags="--static" \
      --prefix="$DEST_DIR" \
      --bindir="$DEST_DIR/bin" \
      --extra-cflags="-I $DEST_DIR/include/" \
      --extra-ldflags="-L $DEST_DIR/lib/" \
      --extra-libs="-lpthread -lm -lz" \
      --ld=g++ \
      --disable-shared \
      --enable-static \
      --enable-libxml2 \
      --enable-demuxer=dash \
      --enable-nonfree \
      --enable-version3 \
      --disable-crystalhd \
      --disable-ffplay \
      --enable-fontconfig \
      --enable-frei0r \
      --enable-gpl \
      --enable-libaom \
      --enable-libass \
      --enable-libfdk-aac \
      --enable-libfreetype \
      --enable-libfribidi \
      --enable-libmfx \
      --enable-libmp3lame \
      --enable-libnpp \
      --enable-libopencore-amrnb \
      --enable-libopencore-amrwb \
      --enable-libopenjpeg \
      --enable-libopus \
      --enable-librtmp \
      --enable-libspeex \
      --enable-libsoxr \
      --enable-libtheora \
      --enable-libvidstab \
      --enable-libvo-amrwbenc \
      --enable-libvorbis \
      --enable-libvpx \
      --enable-libwebp \
      --enable-libx264 \
      --enable-libx265 \
      --enable-libxvid \
      --enable-libzimg \
      --enable-libzvbi \
      --enable-openssl \
      --enable-pic \
      --disable-sndio \
      --enable-vdpau \
      --extra-version=FFMpeg5.1-XUI-NO-HW
    Make install distclean
    hash -r
}

installLibs
installCUDASDK
installNvidiaSDK

compileNasm
compileYasm
compileFontconfig
compileFrei0r
compileHarfbuzz
compileLibAom
compileLibAss
compileLibdav1d
compileLibdrm
compileLibfdkcc
compileLibFreetype
compileLibFribidi
compileLibmfx
compileLibMP3Lame
compileLibogg
compileLibopencore
compileLibOpus
compileLibpng
compileLibrtmp
compileLibspeex
compileLibSoxr
compileLibtheora
compileLibvidstab
compileLibvoamrwb
compileLibvdpau
compileLibvorbis
compileLibVpx
compileLibwebp
compileLibxcb
compileLibxml2
compileLibX264
compileLibX265
compileLibXv
compileLibxvidcore
compileLibzimg
compileLibzvbi
compileLibOpenJPEG
compileOpenSSL
compileSDL2

compileFfmpeg

echo "Complete!"

## END ##


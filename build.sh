#!/bin/bash
set -e

# Toolchain: clang (for CET/CFI options on x86_64); you can use GCC if you prefer
sudo apt-get update && sudo apt-get install -y build-essential clang cmake nasm \
  autoconf automake libtool git pkg-config libseccomp-dev

# Common hardening flags (prod)
export CFLAGS="-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 \
 -fstack-clash-protection -fno-strict-overflow -fno-delete-null-pointer-checks \
 -fPIE -fcf-protection=full"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-z,relro,-z,now,-z,noexecstack,-z,separate-code -pie"

# 1) libjpeg-turbo (API/ABI compatible with libjpeg, faster)
if [ ! -d "libjpeg-turbo" ]; then
  git clone https://github.com/libjpeg-turbo/libjpeg-turbo.git
fi
cd libjpeg-turbo && mkdir -p build && cd build
cmake -G"Unix Makefiles" .. \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
  -DWITH_JPEG8=ON -DWITH_TURBOJPEG=ON \
  -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS"
make -j"$(nproc)" && sudo make install
cd ../..

# 2) libpng (hardened)
if [ ! -d "libpng" ]; then
  git clone https://github.com/glennrp/libpng.git
fi
cd libpng
make clean || true
./autogen.sh
./configure CC=clang CFLAGS="$CFLAGS -DPNG_SAFE_LIMITS_SUPPORTED" LDFLAGS="$LDFLAGS" --disable-shared --enable-static --disable-hardware-optimizations
make -j"$(nproc)" && sudo make install
cd ..

echo "libjpeg-turbo and libpng have been successfully built and installed with hardening."

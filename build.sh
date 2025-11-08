#!/bin/bash
set -e

# Toolchain: clang (for CET/CFI options on x86_64); you can use GCC if you prefer
sudo apt-get update && sudo apt-get install -y build-essential clang cmake nasm \
  autoconf automake libtool git pkg-config libseccomp-dev librsvg2-dev

# Common hardening flags (prod)
export CFLAGS="-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 \
 -fstack-clash-protection -fno-strict-overflow -fno-delete-null-pointer-checks \
 -fPIE -fcf-protection=full"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-z,relro,-z,now,-z,noexecstack,-z,separate-code -pie"

# Initialize submodules
git submodule update --init --recursive

# 1) libjpeg-turbo (API/ABI compatible with libjpeg, faster)
# Mitigates CVE-2018-14498: heap-based buffer over-read
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
# Mitigates CVE-2015-8540, CVE-2019-7317: buffer overflow in PNG chunk processing
cd libpng
make distclean || true
./autogen.sh
./configure CC=clang CFLAGS="$CFLAGS -DPNG_SAFE_LIMITS_SUPPORTED" LDFLAGS="$LDFLAGS" --disable-shared --enable-static --disable-hardware-optimizations
make -j"$(nproc)" && sudo make install
cd ..

# 3) giflib (hardened)
# Mitigates CVE-2019-15133, CVE-2016-3977: out-of-bounds read vulnerabilities
if [ ! -d "giflib" ]; then
  git clone https://github.com/mirrorer/giflib.git
fi
cd giflib
git fetch --tags
# Use latest stable version (5.2.1 or newer has CVE fixes)
git checkout 5.2.1 2>/dev/null || git checkout master
make distclean || true
make CC=clang CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" -j"$(nproc)"
sudo make install PREFIX=/usr/local
# Ensure library is in standard location
sudo cp libgif.a /usr/local/lib/ || true
sudo cp *.h /usr/local/include/ || true
cd ..

echo "libjpeg-turbo, libpng, and giflib have been successfully built and installed with hardening."

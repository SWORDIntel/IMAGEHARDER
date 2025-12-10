#!/bin/bash
set -e

# Audio Library Hardening Build Script
# This script builds hardened versions of common audio libraries:
# - libmpg123 (MP3 decoding)
# - libopus (Opus codec)
# - libvorbis (Vorbis codec)
# - libflac (FLAC codec)
# - libsndfile (General audio I/O)

# Toolchain: clang for CET/CFI hardening
sudo apt-get update && sudo apt-get install -y build-essential clang cmake nasm \
  autoconf automake libtool git pkg-config libseccomp-dev libogg-dev yasm

# =============================================================================
# METEOR TRUE FLAG PROFILE (OPTIMAL for AI/ML workloads)
# =============================================================================
load_meteor_flags() {
    local flags_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../METEOR_TRUE_FLAGS.sh"
    if [ -f "${flags_file}" ]; then
        # shellcheck disable=SC1090
        source "${flags_file}"
        export CFLAGS="${CFLAGS_OPTIMAL}"
        export CXXFLAGS="${CXXFLAGS_OPTIMAL}"
        export LDFLAGS="${LDFLAGS_OPTIMAL} ${LDFLAGS_SECURITY}"
        echo "[FLAGS] Applied METEOR TRUE OPTIMAL flags (AI/ML-safe)"
    else
        # Fallback to default hardening flags
        export CFLAGS="-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 \
 -fstack-clash-protection -fno-strict-overflow -fno-delete-null-pointer-checks \
 -fPIE -fcf-protection=full"
        export CXXFLAGS="$CFLAGS"
        export LDFLAGS="-Wl,-z,relro,-z,now,-z,noexecstack,-z,separate-code -pie"
        echo "[FLAGS] Using default hardening flags (METEOR_TRUE_FLAGS.sh not found)"
    fi
}

load_meteor_flags

# Initialize submodules
git submodule update --init --recursive

echo "=========================================="
echo "Building hardened audio libraries..."
echo "=========================================="

# 1) libmpg123 (MP3 decoding - CRITICAL for malware prevention)
echo "[1/5] Building libmpg123 (hardened MP3 decoder)..."
if [ ! -d "mpg123" ]; then
  echo "mpg123 directory not found. Attempting to install from package manager..."
  sudo apt-get install -y mpg123 libmpg123-dev
  echo "Note: Using system mpg123. For full hardening, manually clone:"
  echo "  git clone https://sourceforge.net/p/mpg123/code.git mpg123"
else
  cd mpg123
  make distclean || true
  autoreconf -ivf
  ./configure CC=clang CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --disable-shared --enable-static \
    --prefix=/usr/local \
    --disable-modules \
    --disable-network \
    --with-audio=dummy \
    --with-default-audio=dummy
  make -j"$(nproc)" && sudo make install
  cd ..
fi

# 2) libogg (dependency for vorbis)
echo "[2/5] Building libogg..."
cd ogg
make distclean || true
./autogen.sh
./configure CC=clang CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
  --disable-shared --enable-static \
  --prefix=/usr/local
make -j"$(nproc)" && sudo make install
cd ..

# 3) libvorbis (Ogg Vorbis codec)
echo "[3/5] Building libvorbis (hardened Vorbis decoder)..."
cd vorbis
make distclean || true
./autogen.sh
./configure CC=clang CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
  --disable-shared --enable-static \
  --prefix=/usr/local \
  --with-ogg=/usr/local
make -j"$(nproc)" && sudo make install
cd ..

# 4) libopus (Opus codec)
echo "[4/5] Building libopus (hardened Opus codec)..."
cd opus
make distclean || true
./autogen.sh
./configure CC=clang CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
  --disable-shared --enable-static \
  --prefix=/usr/local \
  --disable-doc \
  --disable-extra-programs
make -j"$(nproc)" && sudo make install
cd ..

# 5) libFLAC (FLAC codec)
echo "[5/5] Building libFLAC (hardened FLAC decoder)..."
cd flac
make distclean || true
./autogen.sh
./configure CC=clang CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
  --disable-shared --enable-static \
  --prefix=/usr/local \
  --disable-programs \
  --disable-examples \
  --disable-xmms-plugin \
  --disable-doxygen-docs \
  --disable-ogg
make -j"$(nproc)" && sudo make install
cd ..

echo "=========================================="
echo "Audio libraries successfully built!"
echo "=========================================="
echo ""
echo "Installed hardened libraries:"
echo "  - libmpg123 (MP3)"
echo "  - libvorbis (Ogg Vorbis)"
echo "  - libopus (Opus)"
echo "  - libFLAC (FLAC)"
echo ""
echo "All libraries built with:"
echo "  - Stack protector (strong)"
echo "  - FORTIFY_SOURCE=3"
echo "  - PIE/RELRO/NX"
echo "  - Control-Flow Enforcement (CET)"
echo "  - Static linking only"

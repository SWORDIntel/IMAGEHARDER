#!/bin/bash
#
# IMAGEHARDER Core Image Format Builder
# Builds hardened image decoders with comprehensive security measures
#
set -e

# =============================================================================
# Configuration
# =============================================================================
IMAGEHARDEN_CPU=${IMAGEHARDEN_CPU:-generic}

# Toolchain: clang (for CET/CFI options on x86_64)
sudo apt-get update && sudo apt-get install -y build-essential clang cmake nasm \
  autoconf automake libtool git pkg-config libseccomp-dev librsvg2-dev

# =============================================================================
# METEOR TRUE FLAG PROFILE (OPTIMAL for AI/ML workloads)
# =============================================================================
load_meteor_flags() {
    local flags_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../METEOR_TRUE_FLAGS.sh"
    if [ -f "${flags_file}" ]; then
        # shellcheck disable=SC1090
        source "${flags_file}"
        export COMMON_CFLAGS="${CFLAGS_OPTIMAL}"
        export COMMON_LDFLAGS="${LDFLAGS_OPTIMAL} ${LDFLAGS_SECURITY}"
        echo "[FLAGS] Applied METEOR TRUE OPTIMAL flags (AI/ML-safe)"
    else
        # Fallback to default hardening flags
        export COMMON_CFLAGS="-O2 -g -pipe -fno-omit-frame-pointer -fstack-protector-strong \
-D_FORTIFY_SOURCE=3 -fstack-clash-protection -fPIC -fPIE -fexceptions \
-fvisibility=hidden -fno-strict-aliasing -fno-plt -fno-delete-null-pointer-checks \
-fno-strict-overflow -fcf-protection=full"
        export COMMON_LDFLAGS="-Wl,-z,relro,-z,now,-z,noexecstack,-z,separate-code -pie -Wl,--as-needed"
        echo "[FLAGS] Using default hardening flags (METEOR_TRUE_FLAGS.sh not found)"
    fi
}

load_meteor_flags

# CPU-specific optimizations
case "$IMAGEHARDEN_CPU" in
    host)
        echo "[INFO] Building for Intel Core Ultra 7 165H (Meteor Lake) with AVX2/AVX-VNNI"
        CPU_FLAGS="-march=native -mtune=native -mavx2 -mfma -mbmi -mbmi2 -maes -msha -mpclmul -mvpclmulqdq"
        ;;
    v3)
        echo "[INFO] Building for x86-64-v3 (AVX2 baseline)"
        CPU_FLAGS="-march=x86-64-v3 -mtune=core-avx2"
        ;;
    *)
        echo "[INFO] Building for generic x86-64"
        CPU_FLAGS="-march=x86-64 -mtune=generic"
        ;;
esac

export CFLAGS="$COMMON_CFLAGS $CPU_FLAGS"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$COMMON_LDFLAGS"

echo "[INFO] CPU Profile: $IMAGEHARDEN_CPU"

# =============================================================================
# Initialize submodules
# =============================================================================
git submodule update --init --recursive

# =============================================================================
# Build core image libraries
# =============================================================================
# NOTE: libjpeg-turbo and libpng are now installed via system packages
# or can be built separately. The core formats PNG/JPEG/GIF are handled
# via Rust FFI bindings in image_harden/src/lib.rs
#
# For extended formats (AVIF, JXL, TIFF, OpenEXR, ICC, EXIF), run:
#   ./build_extended_formats.sh

# Build giflib if needed
if [ ! -d "giflib" ]; then
  echo "[INFO] Cloning giflib..."
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

echo ""
echo "================================================================="
echo "Core image libraries built successfully!"
echo "================================================================="
echo ""
echo "Next steps:"
echo "  1. Build extended formats: ./build_extended_formats.sh"
echo "  2. Build audio codecs:     ./build_audio.sh"
echo "  3. Build FFmpeg WASM:      ./build_ffmpeg_wasm.sh"
echo "  4. Build Rust binaries:    cd image_harden && cargo build --release"
echo ""

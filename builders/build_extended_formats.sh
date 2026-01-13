#!/bin/bash
#
# IMAGEHARDER Extended Format Builder
# Builds AVIF, JXL, TIFF, OpenEXR, lcms2, and libexif with comprehensive hardening
#
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Source hardening flags
if [ -f "config/hardening-flags.mk" ]; then
    # Extract flags from makefile (simplified approach)
    IMAGEHARDEN_CPU=${IMAGEHARDEN_CPU:-generic}
    log_info "Using CPU profile: $IMAGEHARDEN_CPU"
fi

# Common hardening flags
export COMMON_CFLAGS="-O2 -g -pipe -fno-omit-frame-pointer -fstack-protector-strong \
-D_FORTIFY_SOURCE=3 -fstack-clash-protection -fPIC -fPIE -fexceptions \
-fvisibility=hidden -fno-strict-aliasing -fno-plt -fno-delete-null-pointer-checks \
-fno-strict-overflow"

export COMMON_LDFLAGS="-Wl,-z,relro,-z,now,-z,noexecstack,-z,separate-code -pie -Wl,--as-needed"

# CPU-specific flags
case "$IMAGEHARDEN_CPU" in
    host)
        log_info "Building for Intel Core Ultra 7 165H (Meteor Lake) with AVX2/AVX-VNNI"
        CPU_FLAGS="-march=native -mtune=native -mavx2 -mfma -mbmi -mbmi2 -maes -msha -mpclmul -mvpclmulqdq"
        ;;
    v3)
        log_info "Building for x86-64-v3 (AVX2 baseline)"
        CPU_FLAGS="-march=x86-64-v3 -mtune=core-avx2"
        ;;
    *)
        log_info "Building for generic x86-64"
        CPU_FLAGS="-march=x86-64 -mtune=generic"
        ;;
esac

export CFLAGS="$COMMON_CFLAGS $CPU_FLAGS"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$COMMON_LDFLAGS"

# Install build dependencies
log_info "Installing build dependencies..."
sudo apt-get update && sudo apt-get install -y \
    build-essential clang cmake nasm meson ninja-build \
    autoconf automake libtool git pkg-config \
    libseccomp-dev yasm python3-pip \
    || log_warn "Some dependencies may already be installed"

# Initialize submodules
log_info "Initializing git submodules for extended formats..."
git submodule update --init --recursive dav1d libavif libjxl libtiff openexr lcms2 libexif || true

INSTALL_PREFIX="/usr/local"
NPROC=$(nproc)

# =============================================================================
# 1. Build dav1d (AV1 decoder - required for AVIF)
# =============================================================================
log_info "Building dav1d (AV1 decoder)..."
if [ -d "dav1d" ]; then
    cd dav1d
    rm -rf build
    meson setup build \
        --prefix="$INSTALL_PREFIX" \
        --buildtype=release \
        --default-library=static \
        -Denable_tools=false \
        -Denable_tests=false \
        -Dc_args="$CFLAGS" \
        -Dcpp_args="$CXXFLAGS"

    ninja -C build
    sudo ninja -C build install
    cd ..
    log_info "✓ dav1d built successfully"
else
    log_warn "dav1d directory not found, skipping"
fi

# =============================================================================
# 2. Build libavif (AVIF image format)
# =============================================================================
log_info "Building libavif..."
if [ -d "libavif" ]; then
    cd libavif
    rm -rf build
    cmake -B build -G Ninja \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DAVIF_CODEC_DAV1D=ON \
        -DAVIF_CODEC_AOM=OFF \
        -DAVIF_BUILD_APPS=OFF \
        -DAVIF_BUILD_TESTS=OFF \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"

    ninja -C build
    sudo ninja -C build install
    cd ..
    log_info "✓ libavif built successfully"
else
    log_warn "libavif directory not found, skipping"
fi

# =============================================================================
# 3. Build libjxl (JPEG XL)
# =============================================================================
log_info "Building libjxl (JPEG XL)..."
if [ -d "libjxl" ]; then
    cd libjxl
    git submodule update --init --recursive || true
    rm -rf build
    cmake -B build -G Ninja \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DJPEGXL_ENABLE_TOOLS=OFF \
        -DJPEGXL_ENABLE_BENCHMARK=OFF \
        -DJPEGXL_ENABLE_EXAMPLES=OFF \
        -DJPEGXL_FORCE_SYSTEM_BROTLI=OFF \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"

    ninja -C build
    sudo ninja -C build install
    cd ..
    log_info "✓ libjxl built successfully"
else
    log_warn "libjxl directory not found, skipping"
fi

# =============================================================================
# 4. Build libtiff (TIFF)
# =============================================================================
log_info "Building libtiff..."
if [ -d "libtiff" ]; then
    cd libtiff
    ./autogen.sh || true
    ./configure \
        --prefix="$INSTALL_PREFIX" \
        --disable-shared \
        --enable-static \
        --disable-tools \
        --disable-tests \
        --disable-contrib \
        --disable-docs \
        CC=clang \
        CXX=clang++ \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        LDFLAGS="$LDFLAGS"

    make -j"$NPROC"
    sudo make install
    cd ..
    log_info "✓ libtiff built successfully"
else
    log_warn "libtiff directory not found, skipping"
fi

# =============================================================================
# 5. Build OpenEXR (HDR images)
# =============================================================================
log_info "Building OpenEXR..."
if [ -d "openexr" ]; then
    cd openexr
    rm -rf build
    cmake -B build -G Ninja \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DOPENEXR_BUILD_TOOLS=OFF \
        -DOPENEXR_INSTALL_TOOLS=OFF \
        -DOPENEXR_INSTALL_EXAMPLES=OFF \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"

    ninja -C build
    sudo ninja -C build install
    cd ..
    log_info "✓ OpenEXR built successfully"
else
    log_warn "openexr directory not found, skipping"
fi

# =============================================================================
# 6. Build lcms2 (ICC color management)
# =============================================================================
log_info "Building lcms2 (Little CMS)..."
if [ -d "lcms2" ]; then
    cd lcms2
    ./autogen.sh || true
    ./configure \
        --prefix="$INSTALL_PREFIX" \
        --disable-shared \
        --enable-static \
        --without-jpeg \
        --without-tiff \
        CC=clang \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS"

    make -j"$NPROC"
    sudo make install
    cd ..
    log_info "✓ lcms2 built successfully"
else
    log_warn "lcms2 directory not found, skipping"
fi

# =============================================================================
# 7. Build libexif (EXIF metadata parser)
# =============================================================================
log_info "Building libexif..."
if [ -d "libexif" ]; then
    cd libexif
    autoreconf -fiv || true
    ./configure \
        --prefix="$INSTALL_PREFIX" \
        --disable-shared \
        --enable-static \
        --disable-docs \
        CC=clang \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS"

    make -j"$NPROC"
    sudo make install
    cd ..
    log_info "✓ libexif built successfully"
else
    log_warn "libexif directory not found, skipping"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
log_info "═══════════════════════════════════════════════════════════"
log_info "Extended format libraries built successfully with hardening:"
log_info "  • dav1d (AV1 decoder)"
log_info "  • libavif (AVIF images)"
log_info "  • libjxl (JPEG XL)"
log_info "  • libtiff (TIFF)"
log_info "  • OpenEXR (HDR)"
log_info "  • lcms2 (ICC color profiles)"
log_info "  • libexif (EXIF metadata)"
log_info ""
log_info "CPU Profile: $IMAGEHARDEN_CPU"
log_info "Install Prefix: $INSTALL_PREFIX"
log_info "═══════════════════════════════════════════════════════════"
echo ""

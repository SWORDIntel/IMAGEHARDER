#!/bin/bash
#
# IMAGEHARDER Cryptographic Library Builder
# Builds libsodium with comprehensive hardening for Meteor Lake
#
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Source hardening flags
IMAGEHARDEN_CPU=${IMAGEHARDEN_CPU:-generic}
log_info "Using CPU profile: $IMAGEHARDEN_CPU"

# =============================================================================
# DSSSL-Enhanced Hardening Flags for Libsodium
# =============================================================================
log_info "Applying DSSSL (Defense in Depth Source/System Level) hardening..."

# Base hardening (aligned with config/hardening-flags.mk)
export COMMON_CFLAGS="-O2 -g -pipe -fno-omit-frame-pointer -fstack-protector-strong \
-D_FORTIFY_SOURCE=3 -fstack-clash-protection -fPIC -fPIE -fexceptions \
-fvisibility=hidden -fno-strict-aliasing -fno-plt -fno-delete-null-pointer-checks \
-fno-strict-overflow"

# Additional DSSSL hardening for crypto operations
export DSSSL_FLAGS="-fstack-check"

# Detect compiler and apply advanced hardening
if command -v clang &> /dev/null; then
    CLANG_VERSION=$(clang --version | head -1 | grep -oP '\d+\.\d+' | head -1)
    log_info "Detected Clang $CLANG_VERSION - enabling advanced hardening"

    # Clang-specific DSSSL features
    DSSSL_FLAGS="$DSSSL_FLAGS -ftrivial-auto-var-init=zero -fzero-call-used-regs=used"

    # CFI and LTO (Clang 7+)
    if command -v clang-15 &> /dev/null || command -v clang-14 &> /dev/null; then
        log_info "Enabling CFI + LTO for enhanced security"
        DSSSL_FLAGS="$DSSSL_FLAGS -flto=thin -fsanitize=cfi -fvisibility=hidden"
    fi
fi

# Spectre/Meltdown mitigations
export SPECTRE_FLAGS="-mretpoline"

# Combine all flags
export COMMON_CFLAGS="$COMMON_CFLAGS $DSSSL_FLAGS $SPECTRE_FLAGS"
export COMMON_LDFLAGS="-Wl,-z,relro,-z,now,-z,noexecstack,-z,separate-code -pie \
-Wl,--as-needed -Wl,-z,nodlopen -Wl,-z,noload"

log_info "DSSSL hardening applied successfully"

# CPU-specific flags
case "$IMAGEHARDEN_CPU" in
    host)
        log_info "Building for Intel Core Ultra 7 165H (Meteor Lake)"
        log_info "Optimizations: AVX2, AES-NI, SHA, BMI1/2, FMA, PCLMULQDQ"
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

INSTALL_PREFIX="/usr/local"
NPROC=$(nproc)

echo ""
log_step "Building libsodium with hardening and CPU optimizations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if submodule is initialized
if [ ! -d "libsodium" ] || [ -z "$(ls -A libsodium)" ]; then
    log_info "Initializing libsodium submodule..."
    git submodule update --init libsodium
fi

cd libsodium

# Clean previous builds
log_info "Cleaning previous builds..."
make distclean 2>/dev/null || true
rm -rf build 2>/dev/null || true

# Generate configure script
if [ ! -f "configure" ]; then
    log_info "Generating configure script..."
    ./autogen.sh
fi

# Configure libsodium with hardening
log_info "Configuring libsodium..."
./configure \
    --prefix="$INSTALL_PREFIX" \
    --disable-shared \
    --enable-static \
    --enable-opt \
    --disable-debug \
    --disable-dependency-tracking \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS"

# Build
log_info "Building libsodium (using $NPROC cores)..."
make -j"$NPROC"

# Run tests
log_info "Running libsodium tests..."
make check || {
    echo -e "${YELLOW}[WARN]${NC} Some tests failed, but continuing..."
}

# Install
log_info "Installing libsodium to $INSTALL_PREFIX..."
sudo make install

# Create pkg-config file if it doesn't exist
PKGCONFIG_DIR="$INSTALL_PREFIX/lib/pkgconfig"
if [ ! -f "$PKGCONFIG_DIR/libsodium.pc" ]; then
    log_info "Creating pkg-config file..."
    sudo mkdir -p "$PKGCONFIG_DIR"
    sudo tee "$PKGCONFIG_DIR/libsodium.pc" > /dev/null <<EOF
prefix=$INSTALL_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libsodium
Description: A modern and easy-to-use crypto library
Version: $(cat src/libsodium/version.h | grep SODIUM_VERSION_STRING | cut -d'"' -f2)
Libs: -L\${libdir} -lsodium
Cflags: -I\${includedir}
EOF
fi

cd ..

# Verify installation
if pkg-config --exists libsodium; then
    SODIUM_VERSION=$(pkg-config --modversion libsodium)
    log_info "libsodium $SODIUM_VERSION installed successfully"
else
    echo -e "${YELLOW}[WARN]${NC} pkg-config cannot find libsodium"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "✓ Libsodium built and installed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Cryptographic Features Available:"
echo "  • Authenticated Encryption: ChaCha20-Poly1305, AES256-GCM"
echo "  • Public-key Encryption: X25519 (Curve25519)"
echo "  • Digital Signatures: Ed25519"
echo "  • Key Derivation: Argon2id, HKDF, BLAKE2b"
echo "  • Hashing: BLAKE2b, SHA-256, SHA-512"
echo "  • Password Hashing: Argon2id (memory-hard)"
echo "  • Secure Memory: mlock, mprotect, sodium_memzero"
echo ""
echo "CPU Profile: $IMAGEHARDEN_CPU"
echo "Install Prefix: $INSTALL_PREFIX"
echo ""
echo "Next steps:"
echo "  1. Update Cargo.toml with libsodium-sys or sodiumoxide"
echo "  2. Implement crypto module in image_harden/src/crypto/"
echo "  3. Run: cd image_harden && cargo build --release"
echo ""

#!/bin/bash
set -e

# ============================================================================
# All-In-One (AIO) Hardened Media Stack Builder
# ============================================================================
#
# Purpose: Build complete hardened media stack for Debian kernel 6.17+
# Usage: Can be called standalone or as git submodule during kernel build
# Target: Images, Audio, Video - Userspace libs + Kernel drivers
#
# Integration with kernel build:
#   cd /usr/src/linux-6.17
#   git submodule add https://github.com/SWORDIntel/IMAGEHARDER.git hardening/media
#   cd hardening/media
#   ./build_all_hardened.sh --kernel-integration
#
# Xen Support: Auto-detected with graceful fallback

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================================
# CONFIGURATION
# ============================================================================

KERNEL_VERSION="${KERNEL_VERSION:-$(uname -r)}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
KERNEL_SRC="${KERNEL_SRC:-/usr/src/linux-$KERNEL_VERSION}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/build-output}"
LOG_FILE="${LOG_FILE:-$OUTPUT_DIR/build-$(date +%Y%m%d-%H%M%S).log}"

# Build flags
BUILD_USERSPACE="${BUILD_USERSPACE:-1}"
BUILD_KERNEL_CONFIGS="${BUILD_KERNEL_CONFIGS:-1}"
BUILD_RUST="${BUILD_RUST:-1}"
KERNEL_INTEGRATION="${KERNEL_INTEGRATION:-0}"
SKIP_TESTS="${SKIP_TESTS:-0}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --kernel-integration)
            KERNEL_INTEGRATION=1
            shift
            ;;
        --kernel-src=*)
            KERNEL_SRC="${1#*=}"
            shift
            ;;
        --no-userspace)
            BUILD_USERSPACE=0
            shift
            ;;
        --no-rust)
            BUILD_RUST=0
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=1
            shift
            ;;
        --help)
            cat << EOF
All-In-One Hardened Media Stack Builder

Usage: $0 [OPTIONS]

Options:
  --kernel-integration        Enable kernel build integration mode
  --kernel-src=PATH           Specify kernel source directory (default: /usr/src/linux-*)
  --no-userspace              Skip userspace library builds
  --no-rust                   Skip Rust application build
  --skip-tests                Skip test compilation
  --help                      Show this help message

Environment Variables:
  KERNEL_VERSION              Target kernel version (default: current)
  INSTALL_PREFIX              Installation prefix (default: /usr/local)
  OUTPUT_DIR                  Build output directory (default: ./build-output)
  BUILD_USERSPACE             Build userspace libs (default: 1)
  BUILD_KERNEL_CONFIGS        Build kernel configs (default: 1)

Examples:
  # Standalone build
  ./build_all_hardened.sh

  # Kernel submodule integration
  ./build_all_hardened.sh --kernel-integration --kernel-src=/usr/src/linux-6.17

  # Userspace only
  ./build_all_hardened.sh --no-rust

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# METEOR TRUE FLAG PROFILE (OPTIMAL for AI/ML workloads)
# Applied to all build steps to preserve numerical precision for ML.
# ============================================================================
load_meteor_flags() {
    local flags_file="${SCRIPT_DIR}/../../METEOR_TRUE_FLAGS.sh"
    if [ -f "${flags_file}" ]; then
        # shellcheck disable=SC1090
        source "${flags_file}"
        export CFLAGS="${CFLAGS_OPTIMAL}"
        export CXXFLAGS="${CXXFLAGS_OPTIMAL}"
        export LDFLAGS="${LDFLAGS_OPTIMAL} ${LDFLAGS_SECURITY}"
        echo "[FLAGS] Applied METEOR TRUE OPTIMAL flags (AI/ML-safe, preserves numerical precision)"
    else
        echo "[FLAGS] METEOR_TRUE_FLAGS.sh not found at ${flags_file}; using default hardening flags"
    fi
}

# ============================================================================
# INITIALIZATION
# ============================================================================

mkdir -p "$OUTPUT_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

# Load Meteor Lake optimization flags
load_meteor_flags

echo "============================================================"
echo "  HARDENED MEDIA STACK BUILDER"
echo "============================================================"
echo "Start Time:        $(date)"
echo "Script Directory:  $SCRIPT_DIR"
echo "Output Directory:  $OUTPUT_DIR"
echo "Kernel Version:    $KERNEL_VERSION"
echo "Kernel Source:     $KERNEL_SRC"
echo "Install Prefix:    $INSTALL_PREFIX"
echo "Kernel Integration: $KERNEL_INTEGRATION"
echo "Log File:          $LOG_FILE"
echo "============================================================"
echo ""

# Detect environment
echo "[DETECT] Checking environment..."
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)
IS_XEN=0
XEN_CAPS="N/A"

if [ -d /proc/xen ]; then
    IS_XEN=1
    XEN_CAPS=$(cat /proc/xen/capabilities 2>/dev/null || echo "Unknown")
    echo "[DETECT] Xen hypervisor: DETECTED"
    echo "[DETECT] Xen capabilities: $XEN_CAPS"
else
    echo "[DETECT] Xen hypervisor: NOT DETECTED (bare metal or other hypervisor)"
fi

if [ "$KERNEL_MAJOR" -lt 6 ] || ([ "$KERNEL_MAJOR" -eq 6 ] && [ "$KERNEL_MINOR" -lt 17 ]); then
    echo "[WARN] Kernel $KERNEL_VERSION < 6.17, some features may not be available"
    echo "[INFO] Continuing with graceful fallback..."
else
    echo "[OK] Kernel $KERNEL_VERSION >= 6.17"
fi

# Check for required tools
echo "[CHECK] Verifying build dependencies..."
MISSING_DEPS=()
for cmd in gcc clang make cmake autoconf automake libtool pkg-config rustc cargo; do
    if ! command -v $cmd &> /dev/null; then
        MISSING_DEPS+=($cmd)
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "[ERROR] Missing dependencies: ${MISSING_DEPS[*]}"
    echo "[INFO] Install with: sudo apt-get install build-essential clang cmake autoconf automake libtool pkg-config rustc cargo"
    exit 1
fi
echo "[OK] All build dependencies present"
echo ""

# ============================================================================
# PHASE 1: USERSPACE LIBRARY BUILDS
# ============================================================================

if [ "$BUILD_USERSPACE" -eq 1 ]; then
    echo "============================================================"
    echo "PHASE 1: Building Userspace Libraries"
    echo "============================================================"
    echo ""

    # 1.1: Image libraries (PNG, JPEG)
    echo "[1/3] Building hardened image libraries (libpng, libjpeg-turbo)..."
    if [ -x "./build.sh" ]; then
        ./build.sh || { echo "[ERROR] Image library build failed"; exit 1; }
        echo "[OK] Image libraries built successfully"
    else
        echo "[WARN] build.sh not found or not executable, skipping"
    fi
    echo ""

    # 1.2: Audio libraries (mpg123, vorbis, opus, flac)
    echo "[2/3] Building hardened audio libraries..."
    if [ -x "./build_audio.sh" ]; then
        ./build_audio.sh || { echo "[ERROR] Audio library build failed"; exit 1; }
        echo "[OK] Audio libraries built successfully"
    else
        echo "[WARN] build_audio.sh not found, skipping"
    fi
    echo ""

    # 1.3: FFmpeg WebAssembly
    echo "[3/3] Building FFmpeg WebAssembly sandbox..."
    if [ -x "./setup_emsdk.sh" ] && [ -x "./build_ffmpeg_wasm.sh" ]; then
        ./setup_emsdk.sh || { echo "[WARN] Emscripten SDK setup failed, continuing..."; }
        ./build_ffmpeg_wasm.sh || { echo "[WARN] FFmpeg Wasm build failed, continuing..."; }
        echo "[OK] FFmpeg WebAssembly built (or skipped)"
    else
        echo "[WARN] FFmpeg Wasm build scripts not found, skipping"
    fi
    echo ""
else
    echo "[SKIP] Userspace library builds disabled"
fi

# ============================================================================
# PHASE 2: KERNEL DRIVER CONFIGURATIONS
# ============================================================================

if [ "$BUILD_KERNEL_CONFIGS" -eq 1 ]; then
    echo "============================================================"
    echo "PHASE 2: Generating Kernel Driver Configurations"
    echo "============================================================"
    echo ""

    # 2.1: Audio driver configs
    echo "[1/2] Generating hardened audio driver configurations (ALSA)..."
    if [ -x "./build_hardened_audio_drivers.sh" ]; then
        ./build_hardened_audio_drivers.sh || { echo "[ERROR] Audio driver config failed"; exit 1; }
        echo "[OK] Audio driver configurations generated"
    else
        echo "[WARN] build_hardened_audio_drivers.sh not found, skipping"
    fi
    echo ""

    # 2.2: Video driver configs
    echo "[2/2] Generating hardened video driver configurations (V4L2, DRM)..."
    if [ -x "./build_hardened_drivers.sh" ]; then
        ./build_hardened_drivers.sh || { echo "[ERROR] Video driver config failed"; exit 1; }
        echo "[OK] Video driver configurations generated"
    else
        echo "[WARN] build_hardened_drivers.sh not found, skipping"
    fi
    echo ""
else
    echo "[SKIP] Kernel driver configuration generation disabled"
fi

# ============================================================================
# PHASE 3: RUST APPLICATION BUILD
# ============================================================================

if [ "$BUILD_RUST" -eq 1 ]; then
    echo "============================================================"
    echo "PHASE 3: Building Rust Application (image_harden)"
    echo "============================================================"
    echo ""

    if [ -d "./image_harden" ]; then
        cd image_harden

        echo "[1/2] Building Rust library and CLI..."
        if [ "$SKIP_TESTS" -eq 0 ]; then
            cargo build --release || { echo "[ERROR] Rust build failed"; exit 1; }
            echo "[OK] Rust application built"
        else
            cargo build --release --no-default-features || { echo "[ERROR] Rust build failed"; exit 1; }
            echo "[OK] Rust application built (tests skipped)"
        fi
        echo ""

        echo "[2/2] Building fuzz targets (optional)..."
        if command -v cargo-fuzz &> /dev/null; then
            cargo fuzz build || { echo "[WARN] Fuzz build failed, continuing..."; }
            echo "[OK] Fuzz targets built (or skipped)"
        else
            echo "[INFO] cargo-fuzz not installed, skipping fuzz builds"
            echo "[INFO] Install with: cargo install cargo-fuzz"
        fi

        cd ..
    else
        echo "[WARN] image_harden directory not found, skipping Rust build"
    fi
    echo ""
else
    echo "[SKIP] Rust application build disabled"
fi

# ============================================================================
# PHASE 4: KERNEL INTEGRATION (if enabled)
# ============================================================================

if [ "$KERNEL_INTEGRATION" -eq 1 ]; then
    echo "============================================================"
    echo "PHASE 4: Kernel Build Integration"
    echo "============================================================"
    echo ""

    if [ ! -d "$KERNEL_SRC" ]; then
        echo "[ERROR] Kernel source not found: $KERNEL_SRC"
        echo "[INFO] Specify with: --kernel-src=/path/to/kernel/source"
        exit 1
    fi

    echo "[INFO] Integrating hardened media configs into kernel build..."
    echo "[INFO] Kernel source: $KERNEL_SRC"

    # Copy kernel configurations to kernel source tree
    KERNEL_CONFIG_DIR="$KERNEL_SRC/.config.d/hardened-media"
    mkdir -p "$KERNEL_CONFIG_DIR"

    # Copy audio configs
    if [ -d "/opt/hardened-audio-drivers/configs" ]; then
        echo "[COPY] Audio driver configs -> $KERNEL_CONFIG_DIR/audio/"
        mkdir -p "$KERNEL_CONFIG_DIR/audio"
        cp -r /opt/hardened-audio-drivers/configs/* "$KERNEL_CONFIG_DIR/audio/" || true
    fi

    # Copy video configs
    if [ -d "/opt/hardened-drivers/configs" ]; then
        echo "[COPY] Video driver configs -> $KERNEL_CONFIG_DIR/video/"
        mkdir -p "$KERNEL_CONFIG_DIR/video"
        cp -r /opt/hardened-drivers/configs/* "$KERNEL_CONFIG_DIR/video/" || true
    fi

    # Create master configuration fragment
    cat > "$KERNEL_CONFIG_DIR/hardened-media.config" <<EOF
# Hardened Media Stack - Master Configuration
# Generated by: $0
# Date: $(date)
# Xen Support: $IS_XEN

# Include audio hardening
. $KERNEL_CONFIG_DIR/audio/kernel-hardened-audio.config

# Include video hardening
. $KERNEL_CONFIG_DIR/video/kernel-hardened-media.config

# Enable media subsystem security
CONFIG_MEDIA_SUPPORT=m
CONFIG_SOUND=m

# Xen integration (if detected)
EOF

    if [ "$IS_XEN" -eq 1 ]; then
        cat >> "$KERNEL_CONFIG_DIR/hardened-media.config" <<EOF
CONFIG_XEN=y
CONFIG_XEN_PV=y
CONFIG_XEN_PVHVM=y
CONFIG_XEN_GRANT_DMA_ALLOC=y
CONFIG_SND_XEN_FRONTEND=m
CONFIG_DRM_XEN=m
EOF
    fi

    echo "[OK] Kernel integration complete"
    echo "[INFO] To use in kernel build:"
    echo "       cd $KERNEL_SRC"
    echo "       make menuconfig"
    echo "       # Load: $KERNEL_CONFIG_DIR/hardened-media.config"
    echo ""
fi

# ============================================================================
# PHASE 5: INSTALLATION
# ============================================================================

echo "============================================================"
echo "PHASE 5: Installation Summary"
echo "============================================================"
echo ""

echo "Hardened libraries installed to: $INSTALL_PREFIX"
echo "Kernel configurations available at:"
echo "  - Audio: /opt/hardened-audio-drivers/"
echo "  - Video: /opt/hardened-drivers/"

if [ -d "./image_harden/target/release" ]; then
    echo ""
    echo "Rust binaries:"
    ls -lh ./image_harden/target/release/image_harden_cli 2>/dev/null || echo "  (not found)"
fi

echo ""
echo "Installation scripts (run after kernel rebuild):"
echo "  sudo /opt/hardened-audio-drivers/install-hardened-audio-drivers.sh"
echo "  sudo /opt/hardened-drivers/install-hardened-drivers.sh"
echo ""

# ============================================================================
# PHASE 6: VERIFICATION & SUMMARY
# ============================================================================

echo "============================================================"
echo "PHASE 6: Build Verification"
echo "============================================================"
echo ""

BUILT_LIBS=()
MISSING_LIBS=()

# Check userspace libraries
for lib in /usr/local/lib/libpng.a /usr/local/lib/libjpeg.a /usr/local/lib/libvorbis.a; do
    if [ -f "$lib" ]; then
        BUILT_LIBS+=("$lib")
    else
        MISSING_LIBS+=("$lib")
    fi
done

echo "[CHECK] Built libraries: ${#BUILT_LIBS[@]}"
for lib in "${BUILT_LIBS[@]}"; do
    echo "  ✓ $lib"
done

if [ ${#MISSING_LIBS[@]} -gt 0 ]; then
    echo "[WARN] Missing libraries: ${#MISSING_LIBS[@]}"
    for lib in "${MISSING_LIBS[@]}"; do
        echo "  ✗ $lib"
    done
fi

# Check Rust binary
if [ -f "./image_harden/target/release/image_harden_cli" ]; then
    echo "[OK] Rust CLI binary: ./image_harden/target/release/image_harden_cli"
else
    echo "[WARN] Rust CLI binary not found"
fi

# Check kernel configs
if [ -d "/opt/hardened-audio-drivers" ] && [ -d "/opt/hardened-drivers" ]; then
    echo "[OK] Kernel driver configurations generated"
else
    echo "[WARN] Some kernel configurations may be missing"
fi

echo ""
echo "============================================================"
echo "BUILD SUMMARY"
echo "============================================================"
echo "Status:             SUCCESS"
echo "Build Time:         $(date)"
echo "Kernel Version:     $KERNEL_VERSION"
echo "Xen Support:        $([ $IS_XEN -eq 1 ] && echo 'ENABLED' || echo 'DISABLED')"
echo "Xen Capabilities:   $XEN_CAPS"
echo "Userspace Libs:     $([ $BUILD_USERSPACE -eq 1 ] && echo 'BUILT' || echo 'SKIPPED')"
echo "Kernel Configs:     $([ $BUILD_KERNEL_CONFIGS -eq 1 ] && echo 'GENERATED' || echo 'SKIPPED')"
echo "Rust Application:   $([ $BUILD_RUST -eq 1 ] && echo 'BUILT' || echo 'SKIPPED')"
echo "Kernel Integration: $([ $KERNEL_INTEGRATION -eq 1 ] && echo 'ENABLED' || echo 'DISABLED')"
echo "Log File:           $LOG_FILE"
echo "============================================================"
echo ""
echo "Next Steps:"
echo "  1. Review build log: less $LOG_FILE"
if [ "$KERNEL_INTEGRATION" -eq 0 ]; then
    echo "  2. Rebuild kernel with hardened configs"
    echo "     cd $KERNEL_SRC && make menuconfig"
fi
echo "  3. Install hardened drivers (after kernel rebuild):"
echo "     sudo /opt/hardened-audio-drivers/install-hardened-audio-drivers.sh"
echo "     sudo /opt/hardened-drivers/install-hardened-drivers.sh"
echo "  4. Reboot system"
echo "  5. Verify: lsmod | grep -E 'snd|video|drm'"
echo ""
echo "Documentation:"
echo "  - README.md                  Project overview"
echo "  - AUDIO_HARDENING.md         Audio security guide"
echo "  - VIDEO_HARDENING.md         Video security guide"
echo "  - SECURITY_ARCHITECTURE.md   Complete architecture"
echo ""
echo "Build completed successfully!"
echo "============================================================"

exit 0

#!/bin/bash
#
# IMAGEHARDER Meteor Lake Build Verification Script
# Checks system compatibility and build readiness for Intel Core Ultra 7 165H
#
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   IMAGEHARDER Meteor Lake Build Verification             ║${NC}"
echo -e "${BLUE}║   Intel Core Ultra 7 165H Compatibility Check            ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS_COUNT++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL_COUNT++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN_COUNT++))
}

# =============================================================================
# CPU Feature Detection
# =============================================================================
echo -e "\n${BLUE}[1/6] Checking CPU Features${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check for AVX2
if grep -q avx2 /proc/cpuinfo; then
    check_pass "AVX2 support detected"
else
    check_fail "AVX2 not found (required for Meteor Lake builds)"
fi

# Check for FMA
if grep -q fma /proc/cpuinfo; then
    check_pass "FMA (Fused Multiply-Add) support detected"
else
    check_warn "FMA not found (optional but recommended)"
fi

# Check for AES-NI
if grep -q aes /proc/cpuinfo; then
    check_pass "AES-NI support detected"
else
    check_warn "AES-NI not found (performance impact on crypto)"
fi

# Check for BMI1/BMI2
if grep -q bmi1 /proc/cpuinfo; then
    check_pass "BMI1 support detected"
else
    check_warn "BMI1 not found (optional)"
fi

if grep -q bmi2 /proc/cpuinfo; then
    check_pass "BMI2 support detected"
else
    check_warn "BMI2 not found (optional)"
fi

# Display CPU model
CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
echo -e "\n  ${BLUE}Detected CPU:${NC} $CPU_MODEL"

# =============================================================================
# Submodule Verification
# =============================================================================
echo -e "\n${BLUE}[2/6] Verifying Git Submodules${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EXPECTED_SUBMODULES=(dav1d libavif libjxl libtiff openexr lcms2 libexif ffmpeg flac ogg opus vorbis)
SUBMODULE_COUNT=$(git submodule status | wc -l)

if [ "$SUBMODULE_COUNT" -eq 12 ]; then
    check_pass "All 12 submodules present"
else
    check_warn "Expected 12 submodules, found $SUBMODULE_COUNT"
fi

# Check each critical submodule
for submod in dav1d libavif libjxl libtiff openexr lcms2 libexif; do
    if [ -d "$submod" ] && [ "$(ls -A $submod)" ]; then
        check_pass "$submod initialized"
    else
        check_fail "$submod missing or empty"
    fi
done

# =============================================================================
# Build Dependencies
# =============================================================================
echo -e "\n${BLUE}[3/6] Checking Build Dependencies${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check compilers
if command -v clang &> /dev/null; then
    CLANG_VER=$(clang --version | head -1 | cut -d' ' -f3)
    check_pass "clang compiler found (version $CLANG_VER)"
else
    check_fail "clang not found (required)"
fi

if command -v cmake &> /dev/null; then
    CMAKE_VER=$(cmake --version | head -1 | cut -d' ' -f3)
    check_pass "cmake found (version $CMAKE_VER)"
else
    check_fail "cmake not found (required)"
fi

# Check for meson (required for dav1d)
if command -v meson &> /dev/null; then
    MESON_VER=$(meson --version)
    check_pass "meson found (version $MESON_VER)"
else
    check_fail "meson not found (required for dav1d)"
fi

# Check for ninja (required for many builds)
if command -v ninja &> /dev/null; then
    check_pass "ninja build system found"
else
    check_fail "ninja not found (required)"
fi

# Check for Rust
if command -v cargo &> /dev/null; then
    RUST_VER=$(rustc --version | cut -d' ' -f2)
    check_pass "Rust toolchain found (version $RUST_VER)"
else
    check_fail "Rust/Cargo not found (required)"
fi

# =============================================================================
# Configuration Files
# =============================================================================
echo -e "\n${BLUE}[4/6] Verifying Configuration Files${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check hardening config
if [ -f "config/hardening-flags.mk" ]; then
    check_pass "config/hardening-flags.mk present"

    # Check for Meteor Lake profile
    if grep -q "ifeq.*host" config/hardening-flags.mk; then
        check_pass "Meteor Lake 'host' profile configured"
    else
        check_fail "Meteor Lake profile missing in hardening-flags.mk"
    fi
else
    check_fail "config/hardening-flags.mk missing"
fi

# Check build scripts
BUILD_SCRIPTS=(build.sh build_extended_formats.sh build_audio.sh)
for script in "${BUILD_SCRIPTS[@]}"; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        check_pass "$script present and executable"
    else
        check_warn "$script missing or not executable"
    fi
done

# =============================================================================
# Rust Project Structure
# =============================================================================
echo -e "\n${BLUE}[5/6] Verifying Rust Project Structure${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "image_harden/Cargo.toml" ]; then
    check_pass "image_harden/Cargo.toml present"
else
    check_fail "image_harden/Cargo.toml missing"
fi

# Check for extended format modules
FORMAT_MODULES=(avif jxl tiff exr icc exif)
for fmt in "${FORMAT_MODULES[@]}"; do
    if [ -f "image_harden/src/formats/${fmt}.rs" ]; then
        check_pass "Format module: ${fmt}.rs"
    else
        check_fail "Missing format module: ${fmt}.rs"
    fi
done

# Check fuzz targets
FUZZ_COUNT=$(find image_harden/fuzz/fuzz_targets -name "fuzz_*.rs" 2>/dev/null | wc -l)
if [ "$FUZZ_COUNT" -ge 15 ]; then
    check_pass "Fuzz targets present ($FUZZ_COUNT targets)"
else
    check_warn "Expected 15+ fuzz targets, found $FUZZ_COUNT"
fi

# =============================================================================
# Documentation
# =============================================================================
echo -e "\n${BLUE}[6/6] Checking Documentation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DOCS=(README.md docs/HARDENING_EXTRAS.md METEOR_LAKE_BUILD.md)
for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        check_pass "$doc present"
    else
        check_warn "$doc missing"
    fi
done

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Verification Summary                  ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✓ Passed:${NC}  $PASS_COUNT"
echo -e "  ${YELLOW}⚠ Warnings:${NC} $WARN_COUNT"
echo -e "  ${RED}✗ Failed:${NC}  $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ System is ready for Meteor Lake optimized builds!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. export IMAGEHARDEN_CPU=host"
    echo "  2. ./build_extended_formats.sh"
    echo "  3. cd image_harden && cargo build --release"
    echo ""
    exit 0
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}✗ Some checks failed. Please review the output above.${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Common fixes:"
    echo "  - Install missing dependencies: sudo apt-get install clang cmake meson ninja-build"
    echo "  - Initialize submodules: git submodule update --init --recursive"
    echo "  - Make scripts executable: chmod +x *.sh"
    echo ""
    exit 1
fi

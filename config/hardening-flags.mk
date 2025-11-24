# IMAGEHARDER Hardening Flags Profile
# Comprehensive security hardening for all C/C++ components
# Supports Intel Core Ultra 7 165H (Meteor Lake) CPU-specific optimizations

# =============================================================================
# COMMON HARDENING FLAGS (Applied to ALL builds)
# =============================================================================

HARDEN_CFLAGS_COMMON := \
  -O2 -g -pipe \
  -fno-omit-frame-pointer \
  -fstack-protector-strong \
  -D_FORTIFY_SOURCE=3 \
  -fstack-clash-protection \
  -fPIC -fPIE \
  -fexceptions \
  -fvisibility=hidden \
  -fno-strict-aliasing \
  -fno-plt \
  -fno-delete-null-pointer-checks \
  -fno-strict-overflow

HARDEN_LDFLAGS_COMMON := \
  -Wl,-z,relro \
  -Wl,-z,now \
  -Wl,-z,noexecstack \
  -Wl,-z,separate-code \
  -pie \
  -Wl,--as-needed

# =============================================================================
# CPU-TUNED FLAGS (Intel Core Ultra 7 165H / Meteor Lake)
# =============================================================================
# Usage: Set IMAGEHARDEN_CPU before building
#   - generic: Fully portable (x86-64 baseline)
#   - v3:      AVX2-class baseline (x86-64-v3)
#   - host:    Intel Core Ultra 7 165H optimized (Meteor Lake)

# Default to generic if not specified
IMAGEHARDEN_CPU ?= generic

ifeq ($(IMAGEHARDEN_CPU),host)
    # Intel Core Ultra 7 165H (Meteor Lake) - Maximum Performance
    # Features: AVX2, AVX-VNNI, AES-NI, SHA, BMI1/2, FMA, PCLMULQDQ
    HARDEN_CFLAGS_CPU := -march=native -mtune=native \
                         -mavx2 -mfma -mbmi -mbmi2 -maes -msha -mpclmul \
                         -mvpclmulqdq
else ifeq ($(IMAGEHARDEN_CPU),v3)
    # AVX2-class baseline (x86-64-v3 microarchitecture level)
    # Compatible with: Haswell, Broadwell, Skylake, and newer
    HARDEN_CFLAGS_CPU := -march=x86-64-v3 -mtune=core-avx2
else
    # Fully portable baseline (x86-64 baseline)
    # Compatible with any x86-64 CPU
    HARDEN_CFLAGS_CPU := -march=x86-64 -mtune=generic
endif

# Combined hardening flags for production builds
HARDEN_CFLAGS  := $(HARDEN_CFLAGS_COMMON) $(HARDEN_CFLAGS_CPU)
HARDEN_LDFLAGS := $(HARDEN_LDFLAGS_COMMON)

# =============================================================================
# SANITIZER & FUZZING FLAGS
# =============================================================================

FUZZ_SAN_FLAGS := -fsanitize=address,undefined -fno-omit-frame-pointer

CFLAGS_FUZZ   := $(HARDEN_CFLAGS_COMMON) $(HARDEN_CFLAGS_CPU) $(FUZZ_SAN_FLAGS)
CXXFLAGS_FUZZ := $(CFLAGS_FUZZ)
LDFLAGS_FUZZ  := $(HARDEN_LDFLAGS_COMMON) -fsanitize=address,undefined

# =============================================================================
# EXPORT FOR USE IN BUILD SCRIPTS
# =============================================================================

export HARDEN_CFLAGS
export HARDEN_CXXFLAGS := $(HARDEN_CFLAGS)
export HARDEN_LDFLAGS
export CFLAGS_FUZZ
export CXXFLAGS_FUZZ
export LDFLAGS_FUZZ

# =============================================================================
# USAGE EXAMPLES
# =============================================================================
#
# Production build (generic):
#   make -f config/hardening-flags.mk IMAGEHARDEN_CPU=generic
#
# Production build (AVX2 baseline):
#   IMAGEHARDEN_CPU=v3 ./build_extended_formats.sh
#
# Host-optimized build (Meteor Lake):
#   IMAGEHARDEN_CPU=host ./build_extended_formats.sh
#
# Fuzzing build:
#   CC=clang CXX=clang++ CFLAGS="$(CFLAGS_FUZZ)" ./build_for_fuzzing.sh
#
# =============================================================================

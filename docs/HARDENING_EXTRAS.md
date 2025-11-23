# IMAGEHARDER // Extended Format & Pipeline Hardening Spec

This document defines the **extended media surface** and the **uniform hardening profile** for all additional formats and hidden-path components in IMAGEHARDER, tuned for:

- **Host**: Intel Core Ultra 7 165H (Meteor Lake, AVX2, AVX-VNNI, AES-NI, SHA, BMI1/2, FMA)
- **OS**: Debian-based, 64-bit only

It is meant to be dropped into the repo as something like:
`docs/HARDENING_EXTRAS.md`

---

## 1. Extended Media Surface

### 1.1 High-Priority Image / Video Extras

These are **additional formats** to be handled with the same security posture as the current core set.

#### AVIF (AV1 Images)

- **Stack**: `libavif` + `dav1d` (preferred) or `libaom`
- **Rationale**:
  - Rapidly increasing usage in browsers and CDNs.
  - AV1 parsing and bitstream handling are complex; bug surface is large.
- **Policy**:
  - Decode-only where possible (no encoder in production builds).
  - Prefer `dav1d` for AV1 decode (hardened, modern codebase).
  - Strict caps on resolution, memory, and file size.

#### JPEG XL (JXL)

- **Stack**: `libjxl`
- **Rationale**:
  - Gaining traction in some pipelines and archives.
  - Large, complex codec; typical "bug farm" characteristics (transforms, containers, etc.).
- **Policy**:
  - Decode-only.
  - Optionally disable advanced or rarely-used features not needed by ingest.

#### TIFF

- **Stack**: `libtiff`
- **Rationale**:
  - Ubiquitous in scanners, medical, GIS, and pro photography.
  - Long history of CVEs and malformed-file exploits.
- **Policy**:
  - Decode-only, no tools/binaries.
  - Restrict supported compressions where possible.
  - Caps on total image size, number of IFDs, and sub-images.

#### OpenEXR / HDR

- **Stack**: `openexr`
- **Rationale**:
  - Common in VFX/HDR workflows and high-end pipelines.
  - Complex format, wide blast radius in creative stacks.
- **Policy**:
  - Decode-only.
  - Restrict to a subset of channel formats actually used downstream.
  - Limit exotic features (deep data, complex channel layouts) by default.

#### MPEG-TS / Raw Transport Streams

- **Stack**: via existing **FFmpeg→WASM** profile
- **Rationale**:
  - Used in live TV/IPTV/CCTV and some "headless" streaming setups.
  - TS demuxers frequently produce CVEs (container + stream parsing).
- **Policy**:
  - Only handled in FFmpeg→WASM sandbox, never native.
  - Max duration, bitrate, and container size enforced by wrapper.

---

### 1.2 Hidden Components in the Render Path

These are not "formats" in the usual sense but **supporting libraries** that are part of the render pipeline and must be hardened to the same standard.

#### ICC / Color Profiles

- **Library**: `lcms2`
- **Threat**:
  - ICC data embedded in PNG/JPEG/other images can trigger parsing edge cases.
  - Historically a source of parsing vulnerabilities.
- **Policy**:
  - Default: strip ICC profiles in hardened mode.
  - Optional: allow only after strict size/type validation.
  - Hardened `lcms2` build for any case where ICC is preserved.

#### Metadata / EXIF / XMP

- **Libraries**: `libexif`, `exiv2`
- **Threat**:
  - EXIF/XMP/metadata parsing is a separate attack surface from the main decoder.
  - Often overlooked; metadata bombs and malformed tags can cause RCE/DoS.
- **Policy**:
  - Default: strip all EXIF/XMP/IPTC metadata in hardened mode.
  - Parse only when explicitly requested by trusted callers.
  - Hard caps on metadata size and number of tags.

#### Fonts & Shaping

- **Libraries**: `FreeType`, `HarfBuzz`
- **Threat**:
  - Complex shaping and font parsing are frequent bug sources (esp. with untrusted fonts).
  - SVG/PDF/video overlays can pull fonts into the pipeline.
- **Policy**:
  - Option A (preferred for hardened mode): "no complex text" → no untrusted fonts.
  - Option B (if text is required):
    - Only load bundled fonts from a strict allow-list.
    - No user-supplied font files.
    - Caps on glyph count, string length, and font table sizes.

---

## 2. Global Compile & Link Hardening

All C/C++ components (libavif, libjxl, libtiff, openexr, lcms2, libexif, exiv2, FreeType, HarfBuzz, FFmpeg, etc.) must share a **single hardening profile** defined in:

`config/hardening-flags.mk`

### 2.1 Common Hardening Flags

```make
# config/hardening-flags.mk

HARDEN_CFLAGS_COMMON := \
  -O2 -g -pipe \
  -fno-omit-frame-pointer \
  -fstack-protector-strong \
  -D_FORTIFY_SOURCE=3 \
  -fstack-clash-protection \
  -fPIC -fPIE \
  -fexceptions -fvisibility=hidden \
  -fno-strict-aliasing \
  -fno-plt

HARDEN_LDFLAGS_COMMON := \
  -Wl,-z,relro \
  -Wl,-z,now \
  -Wl,-z,noexecstack \
  -pie \
  -Wl,--as-needed
```

These must be **appended** to all library builds:

```make
CFLAGS   += $(HARDEN_CFLAGS)
CXXFLAGS += $(HARDEN_CFLAGS)
LDFLAGS  += $(HARDEN_LDFLAGS)
```

---

## 3. CPU-Tuned Flags (Intel Core Ultra 7 165H)

We provide a **CPU profile switch** controlled by `IMAGEHARDEN_CPU`:

* `generic` – fully portable baseline.
* `v3` – AVX2-class baseline (x86-64-v3-ish).
* `host` – host-optimized for Meteor Lake (used on your laptop).

Add this to `config/hardening-flags.mk`:

```make
# CPU profile selection
# IMAGEHARDEN_CPU = generic | v3 | host

ifeq ($(IMAGEHARDEN_CPU),host)
    # Local builds on Intel Core Ultra 7 165H (Meteor Lake)
    HARDEN_CFLAGS_CPU := -march=native -mtune=native \
                         -mavx2 -mfma -mbmi -mbmi2 -maes -msha -mpclmul \
                         -mvpclmulqdq
else ifeq ($(IMAGEHARDEN_CPU),v3)
    # AVX2-class boxes (x86-64-v3 baseline)
    HARDEN_CFLAGS_CPU := -march=x86-64-v3 -mtune=core-avx2
else
    # Fully portable fallback
    HARDEN_CFLAGS_CPU := -march=x86-64 -mtune=generic
endif

HARDEN_CFLAGS  := $(HARDEN_CFLAGS_COMMON) $(HARDEN_CFLAGS_CPU)
HARDEN_LDFLAGS := $(HARDEN_LDFLAGS_COMMON)
```

### 3.1 Recommended Usage

* **On your laptop (max perf):**

```bash
IMAGEHARDEN_CPU=host ./build.sh
IMAGEHARDEN_CPU=host ./build_audio.sh
IMAGEHARDEN_CPU=host ./build_ffmpeg_wasm.sh
```

* **For CI / AVX2 baseline artifacts:**

```bash
IMAGEHARDEN_CPU=v3 ./build.sh
```

* **For fully portable binaries:**

```bash
IMAGEHARDEN_CPU=generic ./build.sh
```

---

## 4. Sanitizers & Fuzzing Profiles

For **fuzz builds** and CI validation, you want sanitizers layered on top of the same CPU profile.

Add:

```make
FUZZ_SAN_FLAGS := -fsanitize=address,undefined -fno-omit-frame-pointer

CFLAGS_FUZZ   := $(HARDEN_CFLAGS_COMMON) $(HARDEN_CFLAGS_CPU) $(FUZZ_SAN_FLAGS)
LDFLAGS_FUZZ  := $(HARDEN_LDFLAGS_COMMON) -fsanitize=address,undefined
```

Use `CFLAGS_FUZZ` and `LDFLAGS_FUZZ` in:

* AVIF: `libavif` + `dav1d` fuzz targets
* JXL: `libjxl` fuzz targets
* TIFF: `libtiff` fuzz targets
* OpenEXR: `openexr` fuzz targets
* MPEG-TS: container/stream fuzzing via FFmpeg-WASM harness
* lcms2: ICC profile fuzzing
* libexif/exiv2: metadata fuzzing
* FreeType/HarfBuzz: font/shaping fuzzing

---

## 5. Rust FFI Wrapper Hardening (Applies to ALL New Formats)

Every new format should implement a common `HardenedDecoder`-style contract (conceptually) with:

### 5.1 Input Validation

* **Magic bytes / signature**:

  * Verify that the container or image header matches expected magic bytes exactly.
  * Reject any mismatch or ambiguous signature.

* **Header sanity**:

  * Parse minimal header structures before any heavy decode.
  * Reject files with inconsistent or obviously bogus headers.

### 5.2 Resource Limits

* **Max file size**:

  * Typical caps 256–500 MB depending on format (container vs still image).

* **Max dimensions (images)**:

  * AVIF/JXL/TIFF/OpenEXR: hard cap e.g. `16384 x 16384`, stricter defaults in configs.

* **Max duration (streams/videos)**:

  * MPEG-TS, etc.: hard cap e.g. 1 hour.

* **Max frames / tiles / layers**:

  * Reject files that exceed configured frame or tile limits.

### 5.3 Time / Step Limits

* Track decode steps (e.g., frames, tiles, chunks).
* Abort if a configured maximum step count is exceeded.
* Optional wall-clock watchdog enforced in sandbox process.

### 5.4 Memory Quotas

* Estimate memory usage (`width * height * channels * bytes_per_pixel`) before allocating.
* Reject any decode request exceeding configured memory limit.

### 5.5 Fail-Closed Error Handling

* Any warning or non-trivial error from the underlying C/C++ library → treat as a hard error.
* Never "best-effort" decode partially corrupted inputs.
* On error, return a precise, typed error without leaking more data.

---

## 6. Hidden Path Rules (ICC, Metadata, Fonts)

### 6.1 ICC / lcms2 Policy

* Default hardened mode:

  * Strip ICC profiles.
* If ICC is retained:

  * Hard-cap profile size (e.g. 1–2 MB).
  * Validate:

    * Profile version.
    * Number and type of tags.
    * Tag size bounds.
  * Reject exotic or rarely-used tag types by default.

### 6.2 Metadata / EXIF / exiv2 Policy

* Default hardened mode:

  * Strip EXIF/XMP/IPTC.
* If parsing is requested:

  * Max size (e.g. 1 MB).
  * Max number of tags.
  * Reject non-UTF-8 strings.
  * Optionally drop GPS or fields known to be abused for data exfil / tracking.

### 6.3 Fonts / FreeType / HarfBuzz Policy

* Hardened mode Option A (preferred):

  * No untrusted fonts, no complex shaping; rely on system-safe fallback.
* Hardened mode Option B (if needed):

  * Load only pre-bundled fonts from a strict allow-list.
  * No user-supplied font file paths.
  * Caps on glyph count and string length for shaping.
  * Disable advanced or rarely-used font features where possible.

---

## 7. Sandboxing Model (Shared Across New Helpers)

All new decoding helpers (AVIF/JXL/TIFF/EXR/TS, ICC, metadata, font/text renders) must follow the same sandboxing model used in existing IMAGEHARDER components.

### 7.1 Namespaces & Isolation

* Run in a separate process with:

  * New PID namespace.
  * New mount namespace with minimal filesystem view (input file + scratch dir).
  * New user namespace (unprivileged UID/GID).
  * New network namespace (no network access).

### 7.2 seccomp-bpf Policies

* Only allow:

  * Basic memory syscalls (`mmap`, `munmap`, `brk`, etc.).
  * Simple file I/O (`openat`, `read`, `close`, `fstat`, etc.).
  * No `execve`, `ptrace`, or raw sockets.
* Optionally maintain **per-format** seccomp profiles (e.g., EXR vs TIFF vs AVIF) with a shared base.

### 7.3 Landlock Rules

* Restrict file access to:

  * The single input file (read-only).
  * A single scratch directory (for temporary files) where needed.
* Deny any attempt to access outside these paths.

---

## 8. Fuzzing & CI Coverage (New Targets)

For each new component, add dedicated fuzz targets (e.g. via `cargo-fuzz`) and include them in CI:

* **Image formats:**

  * `fuzz_avif`
  * `fuzz_jxl`
  * `fuzz_tiff`
  * `fuzz_exr`

* **Containers / streams:**

  * `fuzz_mpegts` (via FFmpeg-WASM harness)

* **Hidden-path libs:**

  * `fuzz_icc` (lcms2)
  * `fuzz_exif` (libexif/exiv2)
  * `fuzz_fonts` (FreeType/HarfBuzz glyph/shaping harness)

CI policy:

* Short fuzz runs on each push/PR (few minutes per target).
* Longer periodic fuzzing on nightly or dedicated fuzz branches.

---

## 9. Summary

With these **extra formats**, **hidden-path hardening rules**, and the **Intel-tuned hardening flags**, IMAGEHARDER:

* Extends coverage to AVIF, JXL, TIFF, OpenEXR, MPEG-TS.
* Closes holes around ICC, metadata, and fonts/shaping.
* Keeps binaries hardened and CPU-optimized on Intel Core Ultra 7 165H.
* Maintains a uniform, fail-closed, sandboxed architecture across all media types.

This spec should be treated as the **canonical reference** for adding new formats or adjusting build profiles in IMAGEHARDER.

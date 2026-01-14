# IMAGEHARDER

**Comprehensive Hardened Media Decoder with Extended Format Support**

IMAGEHARDER is a production-grade system for hardening image, audio, and video decoding libraries. It provides comprehensive security measures including CPU-optimized hardening flags, sandboxing, fuzzing infrastructure, and support for extended modern formats.

---

## 📋 Table of Contents

- [Supported Formats](#supported-formats)
- [Security Features](#security-features)
- [CPU Optimization](#cpu-optimization)
- [Getting Started](#getting-started)
- [Build Instructions](#build-instructions)
- [Usage](#usage)
- [Fuzzing](#fuzzing)
- [Architecture](#architecture)
- [Documentation](#documentation)

---

## 🎨 Supported Formats

### Core Image Formats
- **PNG** - libpng with strict limits (CVE-2015-8540, CVE-2019-7317 mitigations)
- **JPEG** - libjpeg-turbo (CVE-2018-14498 mitigation)
- **GIF** - giflib (CVE-2019-15133, CVE-2016-3977 mitigations)
- **WebP** - Pure Rust decoder (CVE-2023-4863 mitigation, HIGH PRIORITY)
- **HEIF/HEIC** - Apple format (iOS/macOS image format)
- **SVG** - resvg (Pure Rust, memory-safe with sanitization)

### Extended Image Formats (NEW)
- **AVIF** - AV1 Image File Format (libavif + dav1d)
- **JPEG XL** - Next-gen lossy/lossless (libjxl)
- **TIFF** - Tagged Image File Format (libtiff, CVE-hardened)
- **OpenEXR** - High Dynamic Range images (VFX/HDR workflows)

### Hidden-Path Components (NEW)
- **ICC Profiles** - Color management (lcms2, with stripping option)
- **EXIF Metadata** - Photo metadata (libexif, with privacy stripping)

### Audio Formats (Pure Rust)
- **MP3** - minimp3 (Rust wrapper)
- **Vorbis** - lewton (pure Rust)
- **FLAC** - claxon (pure Rust)
- **Opus** - opus crate
- **Ogg** - ogg container (pure Rust)

### Video Formats
- **MP4/MOV** - mp4parse (Firefox's Rust implementation)
- **MKV/WebM** - matroska (pure Rust EBML)
- **FFmpeg** - WebAssembly sandboxed (MPEG-TS and others)

---

## 🔒 Security Features

### Compile-Time Hardening
- **Stack Protection**: `-fstack-protector-strong`, `-fstack-clash-protection`
- **Memory Safety**: `-D_FORTIFY_SOURCE=3`, `-fPIE`, `-pie`
- **RELRO**: `-Wl,-z,relro,-z,now`
- **No Executable Stack**: `-Wl,-z,noexecstack`
- **Control Flow**: `-fcf-protection=full` (CET on x86_64)
- **Hidden Symbols**: `-fvisibility=hidden`

### Runtime Protection
- **Strict Resource Limits**:
  - Image dimensions (default: 8192x8192, configurable up to 16384x16384)
  - File sizes (256-500 MB depending on format)
  - IFD counts (TIFF: max 100 IFDs)
  - Tag counts (ICC: max 256, EXIF: max 512)
  - Memory quotas enforced before allocation

- **Input Validation**:
  - Magic byte verification
  - Header sanity checks
  - Dimension bounds checking
  - Container structure validation

- **Fail-Closed Error Handling**:
  - No best-effort decoding
  - Hard errors on warnings
  - No partial data leakage

### Sandboxing
- **Kernel Namespaces** (PID, mount, user, network)
- **seccomp-bpf** syscall filtering
- **Landlock** filesystem access control
- **WebAssembly** sandbox for FFmpeg

### Privacy Protection
- **Default ICC Profile Stripping**: Removes color profiles in hardened mode
- **Default EXIF Stripping**: Removes all metadata including GPS
- **Selective Retention**: Optional validated ICC/EXIF with strict limits

---

## ⚡ CPU Optimization

IMAGEHARDER supports CPU-tuned builds for maximum performance:

### CPU Profiles

| Profile | Target | Use Case |
|---------|--------|----------|
| `generic` | x86-64 baseline | Maximum compatibility |
| `v3` | x86-64-v3 (AVX2) | CI/production (Haswell+) |
| `host` | Native CPU | Development (Intel Core Ultra 7 165H) |

### Build Examples

```bash
# Generic (portable)
IMAGEHARDEN_CPU=generic ./build.sh

# AVX2 baseline (recommended for production)
IMAGEHARDEN_CPU=v3 ./build_extended_formats.sh

# Host-optimized (Meteor Lake: AVX2, AVX-VNNI, AES-NI, SHA)
IMAGEHARDEN_CPU=host ./build_extended_formats.sh
```

### Optimizations Applied
- **Meteor Lake** (`host`): `-march=native -mavx2 -mfma -mbmi -mbmi2 -maes -msha -mpclmul`
- **AVX2** (`v3`): `-march=x86-64-v3 -mtune=core-avx2`
- **Generic**: `-march=x86-64 -mtune=generic`

---

## 🚀 Getting Started

### Prerequisites

#### System Requirements
- Debian-based Linux (Ubuntu, Debian)
- Kernel 5.13+ (for Landlock support)
- 64-bit x86_64 architecture

#### Build Dependencies
```bash
sudo apt-get update && sudo apt-get install -y \
    build-essential clang cmake nasm meson ninja-build \
    autoconf automake libtool git pkg-config \
    libseccomp-dev yasm python3-pip \
    rustc cargo
```

---

## 🔨 Build Instructions

### Quick Start: Unified Installer (Recommended)

The easiest way to install IMAGEHARDER is using the unified installer:

```bash
# Install all components
./install.sh --all

# Install specific components
./install.sh --core --extended --rust

# Interactive mode (menu-driven)
./install.sh

# With CPU profile
IMAGEHARDEN_CPU=host ./install.sh --all

# See all options
./install.sh --help
```

### Manual Build (Advanced)

If you prefer to build components individually:

#### 1. Clone and Initialize

```bash
git clone https://github.com/SWORDIntel/IMAGEHARDER.git
cd IMAGEHARDER
git submodule update --init --recursive
```

#### 2. Build Core Libraries

```bash
# Build core image libraries (GIF, etc.)
./build.sh

# Build extended formats (AVIF, JXL, TIFF, OpenEXR, ICC, EXIF)
./build_extended_formats.sh

# Build audio codecs (optional, Rust uses pure implementations)
./build_audio.sh

# Build FFmpeg WebAssembly sandbox
./setup_emsdk.sh
./build_ffmpeg_wasm.sh
```

#### 3. Build Rust Components

```bash
cd image_harden
cargo build --release
```

#### 4. Run Tests

```bash
cargo test --release
```

---

## 📖 Usage

### Rust API

Add to your `Cargo.toml`:

```toml
[dependencies]
image_harden = { path = "../image_harden" }
```

### Example: Decoding Images

```rust
use image_harden::{decode_png, decode_jpeg, ImageHardenError};

fn main() -> Result<(), ImageHardenError> {
    // Decode PNG with hardening
    let png_data = std::fs::read("image.png")?;
    let decoded = decode_png(&png_data)?;

    // Decode JPEG
    let jpeg_data = std::fs::read("photo.jpg")?;
    let decoded = decode_jpeg(&jpeg_data)?;

    Ok(())
}
```

### Example: Extended Formats

```rust
use image_harden::formats::{avif, jxl, tiff, exr};

fn decode_modern_formats() -> Result<(), ImageHardenError> {
    // AVIF (AV1 images)
    #[cfg(feature = "avif")]
    {
        let avif_data = std::fs::read("image.avif")?;
        let decoded = avif::decode_avif(&avif_data)?;
    }

    // JPEG XL
    #[cfg(feature = "jxl")]
    {
        let jxl_data = std::fs::read("image.jxl")?;
        let decoded = jxl::decode_jxl(&jxl_data)?;
    }

    // TIFF
    #[cfg(feature = "tiff")]
    {
        let tiff_data = std::fs::read("scan.tiff")?;
        let decoded = tiff::decode_tiff(&tiff_data)?;
    }

    // OpenEXR (HDR)
    #[cfg(feature = "openexr")]
    {
        let exr_data = std::fs::read("render.exr")?;
        let decoded = exr::decode_exr(&exr_data)?;
    }

    Ok(())
}
```

### Example: Metadata Handling

```rust
use image_harden::formats::{icc, exif};

fn handle_metadata() -> Result<(), ImageHardenError> {
    // Validate ICC profile
    #[cfg(feature = "icc")]
    {
        let profile_data = std::fs::read("profile.icc")?;
        let info = icc::validate_icc_profile(&profile_data)?;
        println!("ICC version: {}.{}", info.version_major, info.version_minor);
    }

    // Validate EXIF (or strip for privacy)
    #[cfg(feature = "exif")]
    {
        let exif_data = extract_exif_from_jpeg(&jpeg_data)?;
        let info = exif::validate_exif(&exif_data)?;

        // Strip GPS data for privacy
        let sanitized = exif::strip_gps_from_exif(&exif_data)?;
    }

    Ok(())
}
```

---

## 🐛 Fuzzing

IMAGEHARDER includes comprehensive fuzzing infrastructure using `cargo-fuzz`.

### Available Fuzz Targets

#### Core Formats
- `fuzz_png`, `fuzz_jpeg`, `fuzz_gif`
- `fuzz_webp`, `fuzz_heif`, `fuzz_svg`

#### Extended Formats
- `fuzz_avif`, `fuzz_jxl`, `fuzz_tiff`, `fuzz_exr`

#### Hidden-Path Components
- `fuzz_icc`, `fuzz_exif`

#### Audio
- `fuzz_mp3`, `fuzz_vorbis`, `fuzz_flac`, `fuzz_opus`

#### Video
- `fuzz_video_mp4`, `fuzz_video_mkv`

### Running Fuzz Tests

```bash
cd image_harden

# Install cargo-fuzz
cargo install cargo-fuzz

# Run a specific target
cargo fuzz run fuzz_avif

# Run with sanitizers
cargo fuzz run fuzz_tiff -- -max_total_time=60

# Run all targets (CI)
./run_all_fuzz_tests.sh
```

---

## 🏗️ Architecture

### Directory Structure

```
IMAGEHARDER/
├── config/
│   └── hardening-flags.mk       # Centralized hardening configuration
├── image_harden/
│   ├── src/
│   │   ├── lib.rs               # Core decoding functions
│   │   ├── formats/             # Extended format modules
│   │   │   ├── avif.rs
│   │   │   ├── jxl.rs
│   │   │   ├── tiff.rs
│   │   │   ├── exr.rs
│   │   │   ├── icc.rs
│   │   │   └── exif.rs
│   │   ├── metrics.rs           # Prometheus metrics
│   │   └── metrics_server.rs
│   ├── fuzz/
│   │   └── fuzz_targets/        # Fuzzing harnesses
│   ├── build.rs                 # C library FFI binding generation
│   └── Cargo.toml
├── docs/
│   └── HARDENING_EXTRAS.md      # Extended hardening specification
├── build.sh                     # Core library builder
├── build_extended_formats.sh    # Extended format builder
├── build_audio.sh               # Audio codec builder
└── build_ffmpeg_wasm.sh         # FFmpeg WASM builder
```

### Format Coverage Matrix

| Format | Decoder | Hardening | Fuzzing | Sandboxing |
|--------|---------|-----------|---------|------------|
| PNG | libpng | ✅ | ✅ | ✅ |
| JPEG | libjpeg-turbo | ✅ | ✅ | ✅ |
| GIF | giflib | ✅ | ✅ | ✅ |
| WebP | Pure Rust | ✅ | ✅ | ✅ |
| HEIF | libheif-rs | ✅ | ✅ | ✅ |
| SVG | resvg (Rust) | ✅ | ✅ | ✅ |
| AVIF | libavif+dav1d | ✅ | ✅ | 🚧 |
| JPEG XL | libjxl | ✅ | ✅ | 🚧 |
| TIFF | libtiff | ✅ | ✅ | 🚧 |
| OpenEXR | openexr | ✅ | ✅ | 🚧 |
| MP3 | minimp3 (Rust) | ✅ | ✅ | ✅ |
| Vorbis | lewton (Rust) | ✅ | ✅ | ✅ |
| FLAC | claxon (Rust) | ✅ | ✅ | ✅ |
| Opus | opus (Rust) | ✅ | ✅ | ✅ |
| MP4 | mp4parse (Rust) | ✅ | ✅ | ✅ |
| FFmpeg | WASM | ✅ | ✅ | ✅ |

---

## 📚 Documentation

- **[HARDENING_EXTRAS.md](docs/HARDENING_EXTRAS.md)** - Extended format hardening specification
- **[KERNEL_BUILD.md](KERNEL_BUILD.md)** - Kernel configuration for Landlock support
- **[config/hardening-flags.mk](config/hardening-flags.mk)** - Hardening flag reference

### Hardening Specification

The [HARDENING_EXTRAS.md](docs/HARDENING_EXTRAS.md) document defines:
- Extended media surface (AVIF, JXL, TIFF, OpenEXR, MPEG-TS)
- Hidden-path component policies (ICC, EXIF, fonts)
- CPU-tuned compilation profiles
- Sanitizer and fuzzing configurations
- Sandboxing models

---

## 🤝 Contributing

Contributions are welcome! Please ensure:
- All C/C++ code uses hardening flags from `config/hardening-flags.mk`
- New formats include Rust FFI wrappers with validation
- Fuzzing targets are added for new decoders
- Tests pass with sanitizers enabled

---

## 📄 License

MIT License - see LICENSE file for details

---

## 🙏 Acknowledgments

Built on:
- VideoLAN's dav1d (AV1 decoder)
- AOMediaCodec's libavif
- libjxl (JPEG XL Reference Implementation)
- Little CMS (lcms2)
- OpenEXR (Academy Software Foundation)
- FFmpeg Project
- Rust ecosystem (resvg, lewton, claxon, mp4parse, matroska)

---

## 🔐 Security Contact

For security issues, please contact: intel@swordintelligence.airforce

**CVEs Addressed**:
- CVE-2023-4863 (WebP)
- CVE-2019-7317, CVE-2015-8540 (libpng)
- CVE-2018-14498 (libjpeg)
- CVE-2019-15133, CVE-2016-3977 (giflib)
- And many more through comprehensive hardening

---

**Status**: Production-Ready with Extended Format Support (v0.2.0)

**Platform**: Debian-based Linux (x86-64, Intel Core Ultra 7 165H optimized)

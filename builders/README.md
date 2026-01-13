# IMAGEHARDER Build Scripts

This directory contains all build scripts for IMAGEHARDER components.

## Build Scripts

### Core Builds
- **build.sh** - Core image libraries (GIF, PNG, JPEG)
- **build_extended_formats.sh** - Extended formats (AVIF, JXL, TIFF, OpenEXR)
- **build_audio.sh** - Audio codec libraries (MP3, Vorbis, Opus, FLAC)
- **build_ffmpeg_wasm.sh** - FFmpeg WebAssembly sandbox
- **build_all_hardened.sh** - All-in-one hardened media stack builder

### Driver Builds
- **build_hardened_drivers.sh** - Hardened video driver configurations
- **build_hardened_audio_drivers.sh** - Hardened audio driver configurations

### Setup Scripts
- **setup_emsdk.sh** - Emscripten SDK setup for WebAssembly builds
- **setup-cockpit.sh** - Cockpit setup (if applicable)

### Testing & Verification
- **integration-tests.sh** - Integration test suite
- **benchmark.sh** - Benchmark tools
- **test_corpus_generator.sh** - Test corpus generation
- **verify_meteor_lake.sh** - Meteor Lake hardware verification

### Utilities
- **generate-sbom.sh** - Software Bill of Materials generation

## Usage

These scripts are called by the main orchestrator (`install.sh` in the root directory). They can also be run individually:

```bash
# Build core libraries
./builders/build.sh

# Build extended formats
IMAGEHARDEN_CPU=host ./builders/build_extended_formats.sh

# Build audio codecs
./builders/build_audio.sh
```

## CPU Profiles

Set `IMAGEHARDEN_CPU` environment variable:
- `generic` - Generic x86-64 (default)
- `v3` - x86-64-v3 (AVX2 baseline)
- `host` - Native CPU (Meteor Lake optimized)

# Security Architecture Overview

## Complete Media Hardening Stack

This document provides a comprehensive overview of the ImageHarden security architecture, covering all media types (images, audio, video) across all layers (userspace, application, kernel).

---

## Architecture Layers

```
┌──────────────────────────────────────────────────────────────┐
│ Layer 4: Kernel Drivers (V4L2, DRM, ALSA)                   │
│ - Hardened video drivers (build_hardened_drivers.sh)        │
│ - Hardened audio drivers (build_hardened_audio_drivers.sh)  │
│ - Xen hypervisor support with graceful fallback             │
│ - DMA limits, module signing, hardware accel disabled       │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ Layer 3: Userspace Libraries (C, hardened compilation)      │
│ - libpng (build.sh)                                          │
│ - libjpeg-turbo (build.sh)                                   │
│ - mpg123, vorbis, opus, flac (build_audio.sh)              │
│ - Compiler flags: PIE, RELRO, stack protection, CET         │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ Layer 2: Application/Parser Layer (Pure Rust)               │
│ - Image: decode_png(), decode_jpeg(), decode_svg()          │
│ - Audio: decode_mp3(), decode_vorbis(), decode_flac()       │
│ - Video: validate_video_container() (MP4, MKV, AVI)         │
│ - Memory-safe parsers, strict validation                    │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ Layer 1: Sandboxing & Isolation                             │
│ - FFmpeg in WebAssembly (wasmtime)                          │
│ - seccomp-bpf syscall filtering                             │
│ - Kernel namespaces (PID, net, mount)                       │
│ - Landlock filesystem restrictions                          │
│ - Xen PV/HVM domain isolation (if available)                │
└──────────────────────────────────────────────────────────────┘
```

---

## Media Type Coverage Matrix

| Media Type | Userspace Libs | Rust Parsers | Kernel Drivers | Xen Support | Fuzzing |
|------------|---------------|--------------|----------------|-------------|---------|
| **Images** |               |              |                |             |         |
| PNG        | ✅ libpng      | ✅ bindings   | N/A¹           | Indirect²   | ✅       |
| JPEG       | ✅ libjpeg-turbo | ✅ bindings | N/A¹           | Indirect²   | ✅       |
| SVG        | ✅ librsvg     | ✅ ammonia    | N/A¹           | Indirect²   | ✅       |
| **Audio**  |               |              |                |             |         |
| MP3        | ✅ mpg123      | ✅ minimp3    | ✅ ALSA        | ✅ Direct   | ✅       |
| Vorbis     | ✅ libvorbis   | ✅ lewton     | ✅ ALSA        | ✅ Direct   | ✅       |
| FLAC       | ✅ libflac     | ✅ claxon     | ✅ ALSA        | ✅ Direct   | ✅       |
| Opus       | ✅ libopus     | ✅ opus       | ✅ ALSA        | ✅ Direct   | N/A³    |
| **Video**  |               |              |                |             |         |
| MP4/MOV    | ✅ FFmpeg-Wasm | ✅ mp4parse  | ✅ V4L2/DRM    | ✅ Direct   | ✅       |
| MKV        | ✅ FFmpeg-Wasm | ✅ matroska  | ✅ V4L2/DRM    | ✅ Direct   | ✅       |
| WebM       | ✅ FFmpeg-Wasm | ✅ matroska  | ✅ V4L2/DRM    | ✅ Direct   | ✅       |
| AVI        | ✅ FFmpeg-Wasm | ✅ custom    | ✅ V4L2/DRM    | ✅ Direct   | ✅       |

**Notes:**
1. **N/A**: Image codecs don't have kernel drivers (userspace only)
2. **Indirect**: Benefits from kernel-level Xen hardening (memory protection, syscall filtering)
3. **N/A³**: Opus fuzzer not yet implemented (Vorbis covers similar code paths)

---

## Xen Hypervisor Support

### Direct Xen Integration (Audio & Video Kernel Drivers)

**Audio (ALSA):**
- `CONFIG_SND_XEN_FRONTEND=m` - PV sound frontend
- `CONFIG_XEN_GRANT_DMA_ALLOC=y` - Safe grant table DMA
- Persistent grants disabled for security
- Fallback: Standard ALSA if not on Xen

**Video (V4L2/DRM):**
- `CONFIG_XEN_FBDEV_FRONTEND=m` - PV framebuffer
- `CONFIG_DRM_XEN=m` - Xen DRM support
- `CONFIG_DRM_XEN_FRONTEND=m` - DRM frontend for guests
- Grant table DMA for video buffers
- Fallback: Standard DRM/V4L2 if not on Xen

**Kernel-Level:**
- `CONFIG_XEN=y` - Core Xen support
- `CONFIG_XEN_PV=y` - Paravirtualized guests
- `CONFIG_XEN_DOM0=y` - Dom0 support
- `CONFIG_XEN_PVHVM=y` - Hardware-assisted virtualization
- `CONFIG_XEN_GRANT_DMA_IOMMU=y` - IOMMU for DMA isolation
- `CONFIG_SWIOTLB_XEN=y` - Xen-aware SWIOTLB

### Indirect Xen Benefits (Images)

While image codecs (PNG, JPEG, SVG) don't have kernel drivers, they benefit from:
- Kernel-level memory protection enforced by Xen
- syscall filtering via seccomp-bpf (works in Xen guests)
- Landlock filesystem restrictions (kernel 5.13+, Xen compatible)
- Process isolation via namespaces (Xen PV/HVM)

### Graceful Fallback

All Xen-specific features use runtime detection:
```bash
if [ -d /proc/xen ]; then
    # Enable Xen-specific hardening
else
    # Use standard hardening (bare metal, KVM, VMware)
fi
```

No compilation failure if Xen is not available.

---

## Security Limits

### Images
```rust
const MAX_W: u32 = 8192;              // 8192x8192 max
const MAX_H: u32 = 8192;
const MAX_ROWBYTES: usize = SIZE_MAX/4;
const MAX_CHUNK_BYTES: usize = 256 * 1024;  // 256 KB per PNG chunk
```

### Audio
```rust
const MAX_AUDIO_FILE_SIZE: usize = 100 * 1024 * 1024;  // 100 MB
const MAX_AUDIO_DURATION_SECS: u64 = 600;              // 10 minutes
const MAX_SAMPLE_RATE: u32 = 192000;                   // 192 kHz
const MAX_CHANNELS: u16 = 8;
```

### Video
```rust
const MAX_VIDEO_FILE_SIZE: usize = 500 * 1024 * 1024;  // 500 MB
const MAX_VIDEO_DURATION_SECS: u64 = 3600;             // 1 hour
const MAX_VIDEO_WIDTH: u32 = 3840;                     // 4K
const MAX_VIDEO_HEIGHT: u32 = 2160;
const MAX_VIDEO_TRACKS: usize = 8;
```

### Kernel (DMA Buffers)
```c
// Audio: 16 MB per ALSA buffer, 32 MB total PCM
// Video: 100 MB per V4L2 buffer
```

---

## Build Scripts Reference

| Script | Target | Xen Support | Documentation |
|--------|--------|-------------|---------------|
| `build.sh` | PNG, JPEG libs | Indirect | `mission.md` |
| `build_audio.sh` | Audio libs (C) | Indirect | `AUDIO_HARDENING.md` |
| `build_hardened_audio_drivers.sh` | ALSA kernel | **Direct** | `AUDIO_HARDENING.md` |
| `build_hardened_drivers.sh` | V4L2/DRM kernel | **Direct** | `VIDEO_HARDENING.md` |
| `build_ffmpeg_wasm.sh` | FFmpeg Wasm | Indirect | `README.md` |
| `setup_emsdk.sh` | Emscripten SDK | N/A | `README.md` |

---

## Threat Models Addressed

### 1. VM Escape (Video)
- **Attack**: Malformed MP4 metadata triggers hypervisor vulnerability
- **Defense**: Pre-validation with mp4parse (Firefox's parser) before FFmpeg
- **Xen**: Grant table DMA prevents direct host memory access

### 2. CPU Desynchronization (Video)
- **Attack**: Timing-based side channels via codec execution
- **Defense**: Software decoding only (hardware accel disabled)
- **Xen**: PV clock isolation prevents timing attacks

### 3. Malware Delivery (Audio)
- **Attack**: PowerShell script embedded in MP3 metadata
- **Defense**: Pure Rust decoder (minimp3), metadata validation
- **Xen**: Process isolation in guest domain

### 4. Buffer Overflow (Images)
- **Attack**: Integer overflow in PNG chunk size
- **Defense**: Strict chunk limits (256 KB), stack protection
- **Xen**: Kernel memory protection enforced

### 5. DMA Attacks (Kernel)
- **Attack**: Malicious video device DMA writes to host memory
- **Defense**: DMA buffer limits (100 MB), IOMMU enabled
- **Xen**: Grant tables isolate guest DMA

### 6. GPU Exploitation (Video)
- **Attack**: Command injection via hardware video decoder
- **Defense**: Hardware acceleration DISABLED
- **Xen**: No direct GPU passthrough

---

## Compilation Instructions

### 1. Build Userspace Libraries
```bash
# Images
./build.sh

# Audio
./build_audio.sh

# FFmpeg (WebAssembly)
./setup_emsdk.sh
./build_ffmpeg_wasm.sh
```

### 2. Build Kernel Drivers (Debian 6.17+)
```bash
# Audio drivers
./build_hardened_audio_drivers.sh
sudo /opt/hardened-audio-drivers/install-hardened-audio-drivers.sh

# Video drivers
./build_hardened_drivers.sh
sudo /opt/hardened-drivers/install-hardened-drivers.sh
```

### 3. Build Rust Application
```bash
cd image_harden
cargo build --release
```

### 4. Reboot
```bash
sudo reboot
```

---

## Verification

### Check Kernel Modules
```bash
# Audio
lsmod | grep snd
cat /proc/asound/cards

# Video
lsmod | grep -E "v4l2|drm"
ls -l /dev/video*
```

### Check Xen Support
```bash
# Detect Xen
cat /proc/xen/capabilities 2>/dev/null

# Check grant tables
cat /proc/xen/grant_tables 2>/dev/null

# Verify DRM Xen frontend
dmesg | grep -i "xen.*drm\|drm.*xen"

# Verify ALSA Xen frontend
dmesg | grep -i "xen.*snd\|snd.*xen"
```

### Test Media Decoding
```bash
cd image_harden
./target/release/image_harden_cli /path/to/test.mp4
./target/release/image_harden_cli /path/to/test.mp3
./target/release/image_harden_cli /path/to/test.png
```

---

## Fuzzing Coverage

### Active Fuzz Targets
```bash
cd image_harden
cargo fuzz list
```

**Output:**
- `fuzz_png` - PNG decoder
- `fuzz_jpeg` - JPEG decoder
- `fuzz_svg` - SVG sanitizer
- `fuzz_mp3` - MP3 decoder (minimp3)
- `fuzz_vorbis` - Vorbis decoder (lewton)
- `fuzz_flac` - FLAC decoder (claxon)
- `fuzz_audio` - Generic audio (auto-detect)
- `fuzz_video_mp4` - MP4 container parser
- `fuzz_video_mkv` - MKV/WebM container parser
- `fuzz_video_avi` - AVI container parser

### Run Fuzzing
```bash
cargo fuzz run fuzz_video_mp4 -- -max_total_time=3600
```

---

## Documentation Index

| Document | Size | Content |
|----------|------|---------|
| `README.md` | 10 KB | Project overview, quick start |
| `mission.md` | 10 KB | Original image hardening spec |
| `KERNEL_BUILD.md` | 2.7 KB | Kernel compilation guide |
| `AUDIO_HARDENING.md` | 11 KB | Comprehensive audio security guide |
| `VIDEO_HARDENING.md` | 18 KB | Comprehensive video security guide |
| `SECURITY_ARCHITECTURE.md` | This file | Complete security architecture |

---

## Dependencies

### Rust Crates (Cargo.toml)
```toml
# Core
thiserror = "1.0"
libseccomp-rs = "0.1"
nix = "0.27"

# Images
librsvg = "2.54.5"
ammonia = "3.3.0"

# Audio (Pure Rust)
lewton = "0.10"      # Vorbis
claxon = "0.4"       # FLAC
minimp3 = "0.5"      # MP3
opus = "0.3"         # Opus
ogg = "0.9"          # Ogg container

# Video (Pure Rust)
mp4parse = "0.17"    # MP4 (Firefox)
matroska = "0.14"    # MKV/WebM
avi = "0.3"          # AVI

# Sandboxing
wasmtime = "0.39"
wasmtime-wasi = "0.39"
landlock = "0.1"
```

### System Packages (Debian)
```bash
# Build tools
build-essential clang cmake nasm autoconf automake libtool

# Kernel headers (for driver compilation)
linux-headers-$(uname -r)

# Libraries
libseccomp-dev librsvg2-dev libogg-dev

# Xen (optional)
xen-utils-common libxen-dev
```

---

## Known Limitations

1. **Opus Fuzzing**: Not yet implemented (covered by Vorbis fuzzer)
2. **FLV Video**: Not supported (legacy Flash format)
3. **MPEG-TS**: Not supported (requires different parser)
4. **Real-time Audio**: Sandboxing adds latency (not suitable for live audio)
5. **Hardware Accel**: Disabled for security (slower software decode)
6. **Xen Dom0**: Some features require Dom0 privileges

---

## Future Enhancements

- [ ] Opus fuzzer implementation
- [ ] FLV container support (if needed)
- [ ] MPEG-TS container support
- [ ] Hardware accel with GPU process isolation
- [ ] Multi-threaded WebAssembly decoding
- [ ] ML-based anomaly detection
- [ ] Streaming validation (chunked processing)
- [ ] Xen stub domain integration

---

## Security Contact

For security issues, please follow responsible disclosure:
1. Create a private issue on GitHub
2. Email security contact (if configured)
3. Allow 90 days for patching before public disclosure

---

## License

This security hardening framework is provided for defensive purposes. Individual libraries retain their original licenses (LGPL, BSD, MIT, etc.).

## Acknowledgments

- Mozilla Firefox team (mp4parse)
- Xiph.Org Foundation (Vorbis, Opus, FLAC, Ogg)
- Linux Kernel Self-Protection Project (KSPP)
- Xen Project
- Rust Security Response WG

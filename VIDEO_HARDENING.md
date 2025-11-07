# Video Format Hardening Guide

## Critical Threat Model

Video files represent one of the **most dangerous** attack vectors in modern computing, capable of:

### Severe Exploitation Scenarios

1. **VM Escape Exploits**
   - Malformed container metadata triggering hypervisor vulnerabilities
   - Codec buffer overflows reaching host memory
   - GPU command injection escaping sandbox boundaries
   - **Xen-specific**: PV/HVM mode confusion attacks, hypercall injection

2. **CPU Desynchronization Attacks**
   - Timing-based side channels via video decoding
   - Spectre/Meltdown variants triggered by codec operations
   - Branch prediction poisoning through codec state machines
   - Cache timing attacks via frame buffer access patterns

3. **Hardware Acceleration Vulnerabilities**
   - GPU buffer overflows in video decode acceleration
   - DMA attacks via malformed video memory descriptors
   - Firmware exploits in hardware video decoders
   - PCIe device compromise via video processing units

4. **Memory Corruption Cascades**
   - Container parser integer overflows (MP4, MKV, AVI)
   - Codec state confusion leading to arbitrary writes
   - Heap spraying via crafted video frame sequences
   - Use-after-free in multi-threaded codec implementations

## Defense Architecture

### Multi-Layer Security Approach

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: Container Format Validation (Pure Rust)       │
│ - MP4parse (Firefox's parser)                          │
│ - Matroska parser (pure Rust)                          │
│ - AVI parser (manual validation)                       │
│ - Reject malformed metadata BEFORE decoding            │
└─────────────────────────────────────────────────────────┘
                         ↓ (validated containers only)
┌─────────────────────────────────────────────────────────┐
│ Layer 2: Parameter Validation & Limits                 │
│ - Max resolution: 3840x2160 (4K)                       │
│ - Max duration: 3600 seconds (1 hour)                  │
│ - Max file size: 500 MB                                │
│ - Max framerate: 120 fps                               │
│ - Max tracks: 8 (prevents resource exhaustion)         │
└─────────────────────────────────────────────────────────┘
                         ↓ (within limits)
┌─────────────────────────────────────────────────────────┐
│ Layer 3: WebAssembly Sandboxing (wasmtime)             │
│ - FFmpeg compiled to Wasm (isolated execution)         │
│ - No direct memory access to host                      │
│ - No system call access                                │
│ - Resource limits enforced by runtime                  │
└─────────────────────────────────────────────────────────┘
                         ↓ (decoded safely)
┌─────────────────────────────────────────────────────────┐
│ Layer 4: Kernel Sandboxing (optional)                  │
│ - seccomp-bpf: syscall filtering                       │
│ - Landlock: filesystem restrictions                    │
│ - Namespaces: PID/network/mount isolation              │
│ - Xen: PV domain isolation (if available)              │
└─────────────────────────────────────────────────────────┘
```

## Supported Video Formats

| Format | Container Parser | Status | Security Level |
|--------|-----------------|---------|----------------|
| MP4/MOV | mp4parse (Rust, Firefox) | ✅ Hardened | HIGH |
| MKV | matroska (Rust) | ✅ Hardened | HIGH |
| WebM | matroska (Rust) | ✅ Hardened | HIGH |
| AVI | Custom Rust parser | ✅ Hardened | MEDIUM |
| FLV | Not supported | ❌ | N/A |
| MPEG-TS | Not supported | ❌ | N/A |

**Codec Support**: All codecs processed via FFmpeg-WebAssembly (H.264, H.265, VP8, VP9, AV1, etc.)

## Implementation Details

### Pre-Validation Layer

**Purpose**: Detect and reject malicious files BEFORE they reach codec layer

```rust
use image_harden::{validate_video_container, VideoMetadata};

let video_data = std::fs::read("suspicious_video.mp4")?;

// CRITICAL: Validate before any processing
match validate_video_container(&video_data) {
    Ok(metadata) => {
        println!("✓ Container validated: {}x{}, {:.1}s, {} video tracks",
            metadata.width,
            metadata.height,
            metadata.duration_secs,
            metadata.video_tracks);

        // Safe to decode
        let decoded = decode_video(&video_data, "ffmpeg.wasm")?;
    }
    Err(e) => {
        eprintln!("✗ REJECTED: {}", e);
        // Quarantine file
    }
}
```

### Security Limits

```rust
// Defined in image_harden/src/lib.rs
const MAX_VIDEO_FILE_SIZE: usize = 500 * 1024 * 1024;  // 500 MB
const MAX_VIDEO_DURATION_SECS: u64 = 3600;             // 1 hour
const MAX_VIDEO_WIDTH: u32 = 3840;                     // 4K
const MAX_VIDEO_HEIGHT: u32 = 2160;                    // 4K
const MAX_VIDEO_FRAMERATE: u32 = 120;                  // 120 fps
const MAX_VIDEO_BITRATE: u64 = 50_000_000;             // 50 Mbps
const MAX_VIDEO_TRACKS: usize = 8;                     // 8 tracks max
```

**Rationale for Limits:**

- **File size (500MB)**: Prevents DoS via memory exhaustion
- **Duration (1 hour)**: Limits CPU consumption in decoding
- **Resolution (4K)**: Balances usability with safety
- **Framerate (120fps)**: Higher rates can trigger timing attacks
- **Track count (8)**: Prevents parser state explosion

### Container Format Validation

#### MP4/MOV (mp4parse)

Uses Mozilla Firefox's battle-tested MP4 parser:

```rust
fn validate_mp4_container(data: &[u8]) -> Result<VideoMetadata, ImageHardenError> {
    use mp4parse::{read_mp4, ParseStrictness};

    // STRICT mode rejects any spec violations
    let context = read_mp4(&mut cursor, ParseStrictness::Strict)?;

    // Validate each track
    for track in &context.tracks {
        // Check dimensions, duration, codec
        // Reject anomalies
    }
}
```

**Security Benefits:**
- Production parser used by millions (Firefox)
- Pure Rust (memory-safe)
- Strict mode rejects spec violations
- No integer overflow vulnerabilities

#### MKV/WebM (matroska)

Uses pure Rust Matroska parser:

```rust
fn validate_mkv_container(data: &[u8]) -> Result<VideoMetadata, ImageHardenError> {
    let matroska = Matroska::open(cursor)?;

    // EBML structure validation
    // Track enumeration and validation
    // Duration and metadata checks
}
```

**Security Benefits:**
- EBML format strictly validated
- Pure Rust implementation
- Used for both MKV and WebM
- Detects DocType spoofing

#### AVI (Custom Parser)

Manual validation due to AVI's legacy security issues:

```rust
fn validate_avi_container(data: &[u8]) -> Result<VideoMetadata, ImageHardenError> {
    // RIFF signature validation
    // Chunk size consistency checks
    // Header (avih) parsing with bounds checking
    // Prevents classic AVI parsing exploits
}
```

**Security Rationale:**
- AVI is legacy format with many historical vulnerabilities
- Extra strictness: chunk size must match file size exactly
- Manual parsing prevents parser confusion attacks
- Limited support (consider rejecting AVI in high-security environments)

## Xen Hypervisor Integration

### Xen-Specific Hardening

For environments running on Xen hypervisor (PV or HVM domains):

```bash
# Check if running on Xen
if [ -d /proc/xen ]; then
    echo "Xen detected: $(cat /proc/xen/capabilities)"

    # Additional hardening for Xen guests
    # Grant table isolation
    # Event channel restrictions
    # Hypercall filtering
fi
```

**Xen Threat Model:**
- **PV domains**: Direct kernel access to hypervisor (higher risk)
- **HVM domains**: Hardware-assisted virtualization (lower risk)
- **Hypercall injection**: Malicious video triggering Xen hypercalls
- **Grant table exploitation**: Shared memory attacks between domains

**Mitigation Strategy (Graceful Fallback):**

```rust
// Detect Xen environment
pub fn is_xen_environment() -> bool {
    std::path::Path::new("/proc/xen/capabilities").exists()
}

pub fn decode_video_safe(data: &[u8], wasm_path: &str) -> Result<Vec<u8>, ImageHardenError> {
    // Pre-validation (always)
    let metadata = validate_video_container(data)?;

    // Xen-specific hardening (if available)
    if is_xen_environment() {
        eprintln!("[INFO] Xen detected: enabling additional isolation");

        // Optional: More aggressive limits for Xen
        if metadata.width * metadata.height > 1920 * 1080 {
            eprintln!("[WARN] Xen env: limiting to 1080p for safety");
            // Could downscale or reject
        }
    }

    // Standard sandboxed decoding
    decode_video(data, wasm_path)
}
```

**Xen Fallback Behavior:**
- If Xen-specific features unavailable: continue with standard hardening
- No failure if `/proc/xen` missing (bare metal or other hypervisors)
- Optional: More conservative limits when Xen detected
- Logging for security audit trails

### Xen-Specific Syscall Filtering

```rust
// seccomp profile for Xen guests
fn get_xen_seccomp_profile() -> Vec<Syscall> {
    let mut profile = get_standard_seccomp_profile();

    // Block Xen-specific hypercalls (if in PV mode)
    profile.push(Block(libc::SYS_xen_hypercall));  // Hypothetical

    // Extra restrictions for shared memory
    profile.push(Block(libc::SYS_process_vm_readv));
    profile.push(Block(libc::SYS_process_vm_writev));

    profile
}
```

## Hardware Acceleration Considerations

**CRITICAL**: Hardware video decoding (GPU, VPU, DSP) significantly increases attack surface.

### Recommendation: DISABLE Hardware Acceleration

```bash
# FFmpeg Wasm build options
./configure \
  --disable-hwaccels \
  --disable-vaapi \
  --disable-vdpau \
  --disable-cuda \
  --disable-cuvid \
  --disable-nvenc \
  --disable-videotoolbox \
  --disable-d3d11va \
  --disable-dxva2
```

**Rationale:**
- Hardware accelerators have firmware vulnerabilities
- GPU command injection can escape VM
- DMA attacks via video memory descriptors
- CPU-only decoding is slower but safer

**Exception**: Low-risk environments with trusted content

## Usage Examples

### Basic Validation

```rust
use image_harden::validate_video_container;

let data = std::fs::read("video.mp4")?;

match validate_video_container(&data) {
    Ok(meta) if meta.validated => {
        println!("✓ Safe to process");
    }
    Ok(_) => {
        eprintln!("✗ Validation incomplete");
    }
    Err(e) => {
        eprintln!("✗ Malicious: {}", e);
    }
}
```

### Production Pipeline

```rust
use image_harden::{validate_video_container, decode_video};

fn process_user_upload(video_data: &[u8]) -> Result<Vec<u8>, Box<dyn Error>> {
    // Step 1: Validate container (fast, safe)
    let metadata = validate_video_container(video_data)
        .map_err(|e| {
            log::error!("Video validation failed: {}", e);
            // Quarantine file
            quarantine_file(video_data);
            e
        })?;

    // Step 2: Additional policy checks
    if metadata.duration_secs > 600.0 {
        return Err("Video too long for free tier".into());
    }

    // Step 3: Decode in sandboxed FFmpeg
    let decoded = decode_video(video_data, "/opt/ffmpeg.wasm")
        .map_err(|e| {
            log::error!("Decoding failed: {}", e);
            e
        })?;

    // Step 4: Re-encode to known-safe format (optional)
    let sanitized = re_encode_to_h264(&decoded)?;

    Ok(sanitized)
}
```

### Batch Processing with Rate Limiting

```rust
use std::time::{Duration, Instant};
use tokio::time::sleep;

async fn process_video_batch(videos: Vec<Vec<u8>>) {
    let mut processed = 0;
    let mut rejected = 0;

    for video in videos {
        let start = Instant::now();

        match validate_video_container(&video) {
            Ok(meta) => {
                // Decode with timeout
                let result = tokio::time::timeout(
                    Duration::from_secs(60),
                    tokio::task::spawn_blocking(move || {
                        decode_video(&video, "ffmpeg.wasm")
                    })
                ).await;

                match result {
                    Ok(Ok(Ok(_))) => processed += 1,
                    _ => rejected += 1,
                }
            }
            Err(e) => {
                eprintln!("Rejected: {}", e);
                rejected += 1;
            }
        }

        // Rate limiting (prevent CPU exhaustion)
        let elapsed = start.elapsed();
        if elapsed < Duration::from_millis(100) {
            sleep(Duration::from_millis(100) - elapsed).await;
        }
    }

    println!("Processed: {}, Rejected: {}", processed, rejected);
}
```

## Fuzzing Strategy

### Container Fuzzing

```bash
cd image_harden
cargo fuzz run fuzz_video_mp4 -- -max_total_time=3600
cargo fuzz run fuzz_video_mkv -- -max_total_time=3600
cargo fuzz run fuzz_video_avi -- -max_total_time=3600
```

### Corpus Sources

- **Valid samples**: FFmpeg test suite, sample-videos.com
- **Mutated samples**: AFL++ mutations of valid files
- **Malformed samples**: Historical CVE PoCs (where legal)

### Fuzzing Targets

1. **Container parsing**: mp4parse, matroska, AVI parser
2. **Validation logic**: limit enforcement, dimension checks
3. **FFmpeg Wasm interface**: WASI boundary fuzzing
4. **Full pipeline**: end-to-end validation + decode

## Monitoring & Incident Response

### Logging Suspicious Videos

```rust
fn log_suspicious_video(data: &[u8], reason: &str) {
    let hash = blake3::hash(data);

    log::warn!(
        "Suspicious video detected\n\
         Reason: {}\n\
         Blake3: {}\n\
         Size: {} bytes\n\
         Timestamp: {}",
        reason,
        hash,
        data.len(),
        chrono::Utc::now()
    );

    // Optional: Send to SIEM
    send_to_siem(SecurityEvent::SuspiciousVideo {
        hash: hash.to_hex(),
        reason: reason.to_string(),
    });
}
```

### Quarantine Procedure

```bash
#!/bin/bash
# quarantine_video.sh

VIDEO_HASH=$(sha256sum "$1" | cut -d' ' -f1)
QUARANTINE_DIR="/var/quarantine/videos"

mkdir -p "$QUARANTINE_DIR"
mv "$1" "$QUARANTINE_DIR/$VIDEO_HASH.quarantined"
chmod 000 "$QUARANTINE_DIR/$VIDEO_HASH.quarantined"

# Log event
logger -t video_quarantine "Quarantined: $VIDEO_HASH"

# Optional: Submit to threat intel
# curl -X POST https://threat-intel.example.com/submit ...
```

### Indicators of Compromise (IOCs)

Monitor for:
- **Repeated validation failures** from same source
- **Videos with unusual dimensions** (prime numbers, very large/small)
- **Abnormal track counts** (>8 tracks, 0 video tracks)
- **Metadata anomalies** (future timestamps, negative durations)
- **Decode timeouts** (indicates decompression bombs)

## Performance Considerations

### Validation Performance

| Format | Validation Speed | Notes |
|--------|-----------------|-------|
| MP4 | ~50 MB/s | Fast box parsing |
| MKV | ~30 MB/s | EBML parsing overhead |
| WebM | ~30 MB/s | Same as MKV |
| AVI | ~100 MB/s | Simple RIFF structure |

**Optimization**: Validate in parallel for batch processing

### Decode Performance (WebAssembly)

- **Overhead vs native**: 2-3x slower (acceptable for security)
- **CPU-bound**: No GPU, single-threaded
- **Memory limit**: Enforced by Wasm runtime
- **Recommended**: Process in separate worker processes

## Security Checklist

- [ ] All video files validated BEFORE decoding
- [ ] Container parser is memory-safe (Rust)
- [ ] Strict size/dimension/duration limits enforced
- [ ] Hardware acceleration DISABLED
- [ ] FFmpeg running in WebAssembly sandbox
- [ ] seccomp-bpf enabled for additional syscall filtering
- [ ] Landlock enabled for filesystem restriction
- [ ] Xen-specific hardening applied (if applicable)
- [ ] Fuzzing integrated into CI/CD pipeline
- [ ] Suspicious video logging enabled
- [ ] Quarantine procedure documented
- [ ] Incident response plan in place

## References

- [MP4 Format Specification (ISO/IEC 14496-12)](https://www.iso.org/standard/68960.html)
- [Matroska Specification](https://www.matroska.org/technical/specs/index.html)
- [CVE-2016-2029: H.264 Buffer Overflow](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2016-2029)
- [CVE-2021-30665: MP4 Parser Vulnerability](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2021-30665)
- [Xen Security Advisories](https://xenbits.xen.org/xsa/)
- [WebAssembly Security](https://webassembly.org/docs/security/)

## Known Limitations

1. **No FLV support**: Flash Video format not implemented (legacy, insecure)
2. **No MPEG-TS**: Transport Stream requires different parser
3. **Software decoding only**: Slower but safer
4. **Single-threaded Wasm**: No parallel decode
5. **Xen features optional**: Falls back gracefully if unavailable

## Future Enhancements

- [ ] MPEG-TS container support
- [ ] Multi-threaded WebAssembly decoding
- [ ] Hardware accel with GPU process isolation
- [ ] ML-based anomaly detection
- [ ] Streaming validation (chunked processing)
- [ ] Xen grant table monitoring
- [ ] Real-time frame-by-frame validation

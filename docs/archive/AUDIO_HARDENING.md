# Audio Library Hardening Guide

## Overview

This document describes the hardening approach for audio decoding libraries on Debian-based systems. Audio files (MP3, Ogg Vorbis, Opus, FLAC) can be vectors for malware delivery, including:

- Embedded malicious payloads (e.g., PowerShell scripts in MP3 metadata)
- Buffer overflow exploits in codec implementations
- Parser vulnerabilities in container formats
- Denial-of-service attacks via malformed headers

## Threat Model

### Real-World Attack Scenarios

1. **Malware in MP3 Files**: Attackers embed PowerShell scripts or other executables in MP3 metadata or as fake audio frames. When processed by vulnerable software, these can be extracted and executed.

2. **Codec Vulnerabilities**: Historical vulnerabilities in libvorbis, libopus, and other codecs have allowed arbitrary code execution through specially crafted audio files.

3. **Parser Exploits**: Malformed container formats (Ogg, FLAC) can trigger buffer overflows or integer overflows in parsing code.

4. **Social Engineering**: Audio files sent via messaging platforms (Telegram, Discord, etc.) can appear legitimate while containing malicious payloads.

## Hardened Libraries

This project provides hardened builds of the following audio libraries:

- **libmpg123**: MP3 decoding (MPEG 1.0/2.0/2.5 layers I, II, III)
- **libvorbis**: Ogg Vorbis codec
- **libopus**: Opus codec (used in WebRTC, VoIP)
- **libFLAC**: Free Lossless Audio Codec
- **libogg**: Ogg container format

## Hardening Techniques

### 1. Compile-Time Hardening Flags

All libraries are built with:

```bash
CFLAGS="-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 \
 -fstack-clash-protection -fno-strict-overflow -fno-delete-null-pointer-checks \
 -fPIE -fcf-protection=full"
LDFLAGS="-Wl,-z,relro,-z,now,-z,noexecstack,-z,separate-code -pie"
```

**Protections Enabled:**

- **Stack Protector Strong**: Detects stack buffer overflows
- **FORTIFY_SOURCE=3**: Compile-time buffer overflow detection
- **Stack Clash Protection**: Prevents stack overflow attacks
- **PIE (Position Independent Executable)**: Enables ASLR
- **RELRO (Relocation Read-Only)**: Hardens GOT/PLT
- **NX Stack**: Prevents code execution on stack
- **CET (Control-Flow Enforcement)**: Hardware-based control-flow integrity (Intel CET)

### 2. Static Linking

All libraries are compiled as **static libraries only** (`--disable-shared --enable-static`). This:

- Reduces attack surface by eliminating shared library hijacking
- Enables whole-program optimization
- Prevents LD_PRELOAD attacks
- Makes ROP gadget chains harder to construct

### 3. Minimal Feature Set

Libraries are built with minimal features enabled:

**libmpg123:**
- Network support disabled (`--disable-network`)
- Audio output disabled (`--with-audio=dummy`)
- Module system disabled (`--disable-modules`)

**libFLAC:**
- Programs/tools disabled (`--disable-programs`)
- Examples disabled (`--disable-examples`)
- Plugin support disabled

**libopus:**
- Documentation disabled (`--disable-doc`)
- Extra programs disabled (`--disable-extra-programs`)

### 4. Runtime Limits and Validation

The Rust wrapper library enforces strict limits:

```rust
const MAX_AUDIO_SIZE: usize = 100 * 1024 * 1024;  // 100 MB max file
const MAX_DURATION_SECS: u32 = 600;                // 10 minutes max
const MAX_SAMPLE_RATE: u32 = 192000;               // 192 kHz max
const MAX_CHANNELS: u32 = 8;                       // 8 channels max
```

### 5. Fail-Closed Error Handling

All decoding functions return `Result<T, AudioHardenError>` and:

- Validate input size before processing
- Check magic numbers and file signatures
- Abort on any parsing error (no partial decoding)
- Zero sensitive memory on error paths

### 6. Sandboxing

Audio decoding can optionally run in a sandboxed environment:

- **seccomp-bpf**: Restricts system calls to minimum required set
- **Kernel namespaces**: Isolates PID, network, and mount namespaces
- **Landlock LSM**: Restricts filesystem access to input file only
- **Resource limits**: CPU time, memory, file size limits via rlimit

## Building Hardened Audio Libraries

### Prerequisites

```bash
sudo apt-get install -y build-essential clang cmake nasm \
  autoconf automake libtool git pkg-config libseccomp-dev \
  libogg-dev yasm
```

### Build Process

```bash
./build_audio.sh
```

This script will:

1. Initialize audio library submodules
2. Apply hardening compiler flags
3. Build static libraries with minimal features
4. Install to `/usr/local/lib` and `/usr/local/include`

### Manual mpg123 Setup

If the automated script fails to clone mpg123, install manually:

```bash
# Option 1: Clone from SourceForge
git clone https://git.code.sf.net/p/mpg123/code mpg123

# Option 2: Use system package (less hardened)
sudo apt-get install -y libmpg123-dev
```

## Using the Rust Library

### Adding Dependency

```toml
[dependencies]
image_harden = { path = "./image_harden" }
```

### Decoding Audio Files

```rust
use image_harden::{decode_mp3, decode_opus, decode_vorbis, decode_flac, AudioHardenError};
use std::fs::File;
use std::io::Read;

fn main() -> Result<(), AudioHardenError> {
    // Read audio file
    let mut file = File::open("suspicious_audio.mp3")?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)?;

    // Decode with hardened library
    let decoded_audio = decode_mp3(&buffer)?;

    println!("Successfully decoded audio: {} samples", decoded_audio.len());
    Ok(())
}
```

### Sandboxed Decoding

```rust
use image_harden::sandboxed_decode_audio;

fn main() -> Result<(), AudioHardenError> {
    let audio_data = std::fs::read("untrusted.mp3")?;

    // Decode in sandboxed environment
    let decoded = sandboxed_decode_audio(&audio_data, "mp3")?;

    println!("Decoded {} samples securely", decoded.len());
    Ok(())
}
```

## Fuzzing

Continuous fuzzing is critical for audio libraries due to their complexity:

```bash
cd image_harden
cargo fuzz run fuzz_mp3
cargo fuzz run fuzz_vorbis
cargo fuzz run fuzz_opus
cargo fuzz run fuzz_flac
```

Fuzz targets are integrated into CI and run automatically.

## Security Best Practices

### For Developers

1. **Always validate input size** before passing to decoder
2. **Set resource limits** (CPU time, memory) before decoding
3. **Run decoders in separate processes** for critical applications
4. **Enable all sandboxing features** when processing untrusted audio
5. **Monitor and log** decoding failures for security analysis

### For System Administrators

1. **Keep libraries updated**: Run `git submodule update --recursive` regularly
2. **Enable kernel features**: Ensure kernel supports seccomp, namespaces, Landlock (5.13+)
3. **Apply resource limits**: Use systemd resource limits for services processing audio
4. **Monitor for exploits**: Subscribe to security advisories for audio libraries

## Malware Detection

The library includes optional malware detection features:

### Metadata Scanning

```rust
use image_harden::scan_audio_metadata;

let audio_data = std::fs::read("suspicious.mp3")?;
let scan_result = scan_audio_metadata(&audio_data)?;

if scan_result.contains_suspicious_data {
    eprintln!("WARNING: Suspicious metadata detected!");
    eprintln!("  - Unknown binary data: {} bytes", scan_result.unknown_data_size);
    eprintln!("  - Unusual tags: {:?}", scan_result.suspicious_tags);
}
```

### File Signature Validation

All decoders validate file magic numbers:

- MP3: `0xFF 0xFB` (MPEG frame sync)
- Ogg: `OggS` signature
- FLAC: `fLaC` signature
- Opus: `OpusHead` in Ogg container

## Performance Considerations

Hardening introduces minimal overhead:

- Compile-time flags: ~2-5% performance impact
- Runtime validation: <1% overhead
- Sandboxing: 10-20% overhead (optional, recommended for untrusted input)

For performance-critical applications, consider:

1. Decode trusted audio without sandboxing
2. Use batch processing to amortize sandbox setup cost
3. Enable SIMD optimizations (still safe with hardening flags)

## Verification

### Build Verification

```bash
# Check for hardening flags
readelf -W -l /usr/local/lib/libmpg123.a | grep -E "GNU_STACK|GNU_RELRO"

# Verify static linking
ldd ./image_harden/target/debug/image_harden_cli | grep -E "mp3|opus|vorbis|flac"
# Should show "not a dynamic executable" or no audio libraries

# Check for stack protection
readelf -s /usr/local/lib/libmpg123.a | grep stack_chk_fail
```

### Runtime Testing

```bash
# Test with known-good audio files
./image_harden/target/debug/image_harden_cli test_audio/valid.mp3

# Test with malformed files (should fail gracefully)
./image_harden/target/debug/image_harden_cli test_audio/malformed.mp3

# Fuzz testing
cd image_harden && cargo fuzz run fuzz_mp3 -- -max_total_time=300
```

## Known Limitations

1. **mp3 Submodule**: May require manual installation due to SourceForge access
2. **CET Support**: Requires Intel 11th gen or AMD Zen 3+ CPUs
3. **Landlock**: Requires kernel 5.13+ (Ubuntu 22.04+, Debian 12+)
4. **Performance**: Sandboxing adds latency (not suitable for real-time audio)

## Incident Response

If you detect malware in audio files:

1. **Quarantine the file**: Move to isolated directory
2. **Extract metadata**: Use `ffprobe` or `exiftool` to examine
3. **Submit for analysis**: Send to security team or VirusTotal
4. **Update signatures**: Add to malware detection database
5. **Review logs**: Check for other suspicious files from same source

## References

- [OWASP Input Validation](https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html)
- [CVE Details: Audio Codec Vulnerabilities](https://www.cvedetails.com/vulnerability-list/vendor_id-12113/Xiph.html)
- [Telegram Security Best Practices](https://core.telegram.org/api/end-to-end)
- [Linux Kernel Hardening](https://kernsec.org/wiki/index.php/Kernel_Self_Protection_Project)

## Contributing

To add support for additional audio formats:

1. Add library as git submodule
2. Update `build_audio.sh` with hardening flags
3. Create Rust wrapper in `image_harden/src/lib.rs`
4. Add fuzz target in `image_harden/fuzz/fuzz_targets/`
5. Update documentation

## License

This hardening framework is provided as-is for security research and defensive purposes. Individual audio libraries retain their original licenses (LGPL, BSD, etc.).

# ImageHarden

ImageHarden is a comprehensive system for hardening image and audio decoding libraries on Debian-based systems. It provides scripts and a Rust library to build and use hardened versions of media processing libraries, significantly reducing the risk of remote code execution vulnerabilities.

## Supported Libraries

### Image Libraries
- `libpng` - PNG image decoding
- `libjpeg-turbo` - JPEG image decoding
- `librsvg` - SVG rendering
- `ffmpeg` - Video decoding (WebAssembly sandboxed)

### Audio Libraries (NEW!)
- `MP3` - via minimp3 (Rust wrapper)
- `Vorbis` - via lewton (pure Rust)
- `FLAC` - via claxon (pure Rust)
- `Opus` - via opus crate
- `Ogg` - via ogg crate (pure Rust)

## Features

-   **Compile-Time Hardening**: Builds C libraries with comprehensive hardening flags, including stack protectors, FORTIFY_SOURCE=3, RELRO, PIE, and Control-Flow Enforcement Technology (CET).
-   **Pure Rust Audio Decoders**: Audio decoding uses memory-safe Rust implementations (lewton, claxon, minimp3) eliminating entire classes of vulnerabilities.
-   **Strict Runtime Limits**: Rust wrappers enforce strict limits on dimensions, memory usage, duration, sample rates, and channels to prevent DoS attacks.
-   **Fail-Closed Error Handling**: The library fails immediately on any error, never continuing with potentially corrupted data.
-   **CI Fuzzing**: Continuous fuzzing with `cargo-fuzz` for both image and audio decoders to catch vulnerabilities before production.
-   **Safe Rust Wrappers**: Idiomatic Rust API for decoding media, abstracting away unsafe FFI complexities.
-   **Kernel-Level Sandboxing**: Uses `seccomp-bpf`, kernel namespaces, and Landlock for isolated execution environments.
-   **SVG Sanitization**: SVG files sanitized with `ammonia` to remove malicious content before rendering.
-   **FFmpeg Wasm Sandboxing**: FFmpeg compiled to WebAssembly and executed in sandboxed `wasmtime` runtime.
-   **Malware Defense**: Specifically hardens against attacks like embedded PowerShell scripts in MP3 files sent via messaging apps.

## Getting Started

### Prerequisites

-   A Debian-based system (e.g., Ubuntu) with a modern kernel (5.13+ for Landlock). For instructions on how to configure your kernel, see the [Kernel Configuration Guide](KERNEL_BUILD.md).
-   `build-essential`, `clang`, `cmake`, `nasm`, `autoconf`, `automake`, `libtool`, `git`, `pkg-config`, `librsvg2-dev`
-   The Rust toolchain

### Building the Hardened Libraries

**Image Libraries:**
```bash
./build.sh
```

This script will install the necessary dependencies, clone the library source code, and build `libpng` and `libjpeg-turbo` with hardening flags.

**Audio Libraries:**
```bash
./build_audio.sh
```

This script builds hardened versions of `mpg123`, `libvorbis`, `libopus`, `libflac`, and `libogg` with the same security hardening. Note: The Rust library uses pure Rust implementations for most audio formats, so building C libraries is optional.

### Building FFmpeg to Wasm

The `setup_emsdk.sh` script automates the process of downloading and activating the Emscripten SDK.

```bash
./setup_emsdk.sh
```

The `build_ffmpeg_wasm.sh` script automates the process of compiling a minimal, static build of FFmpeg into a `ffmpeg.wasm` file.

```bash
./build_ffmpeg_wasm.sh
```

### Using the Rust Library

The `image_harden` Rust library provides functions for decoding both images and audio:

**Image Decoding:** `decode_png`, `decode_jpeg`, `decode_svg`, `decode_video`
**Audio Decoding:** `decode_mp3`, `decode_vorbis`, `decode_flac`, `decode_audio` (auto-detect)

All functions take a byte slice and return a `Result` containing either the decoded data or an `ImageHardenError`.

To use the library, add it as a dependency to your `Cargo.toml`:

```toml
[dependencies]
image_harden = { path = "./image_harden" }
```

Then, you can use the functions as follows:

```rust
use image_harden::{decode_video, decode_mp3, ImageHardenError};
use std::fs::File;
use std::io::Read;

fn main() -> Result<(), ImageHardenError> {
    // Decode video
    let video_data = std::fs::read("my_video.mp4")?;
    let decoded_video = decode_video(&video_data)?;
    println!("Successfully decoded video: {} bytes", decoded_video.len());

    // Decode audio (safe against malware in MP3 files)
    let audio_data = std::fs::read("suspicious_audio.mp3")?;
    let decoded_audio = decode_mp3(&audio_data)?;
    println!("Decoded {} samples at {} Hz",
        decoded_audio.samples.len(),
        decoded_audio.sample_rate);

    Ok(())
}
```

### Running the Demonstration Binary

The project includes a demonstration binary, `image_harden_cli`, which can be used to test the library. To build and run the binary:

```bash
cd image_harden
cargo build
./target/debug/image_harden_cli /path/to/your/video.mp4
```

### Fuzzing

The project is set up with `cargo-fuzz` for continuous fuzzing of all decoding functions:

```bash
cd image_harden

# Image fuzzing
cargo fuzz run fuzz_png
cargo fuzz run fuzz_jpeg
cargo fuzz run fuzz_svg

# Audio fuzzing
cargo fuzz run fuzz_mp3
cargo fuzz run fuzz_vorbis
cargo fuzz run fuzz_flac
cargo fuzz run fuzz_audio   # Auto-detect format
```

The fuzz tests are integrated into the CI pipeline and run automatically on every push and pull request.

## Security

ImageHarden provides secure-by-default media decoding for both images and audio. The combination of:
- Memory-safe Rust implementations (audio)
- Compile-time hardening (C libraries)
- Strict runtime validation
- Continuous fuzzing
- Kernel sandboxing

...provides robust defense against remote code execution, buffer overflows, and malware delivery via media files.

### Real-World Threat Protection

This system specifically defends against:
- **Embedded malware in audio files** (e.g., PowerShell scripts in MP3 metadata)
- **Codec vulnerabilities** in libvorbis, libopus, libflac
- **Parser exploits** in container formats (Ogg, MP4)
- **Social engineering attacks** via files sent through Telegram, Discord, email

### Sandboxing

The `image_harden_cli` demonstration binary uses a combination of kernel namespaces, `seccomp-bpf`, and Landlock to create a sandboxed environment for image decoding. This provides an additional layer of security by isolating the decoding process from the rest of the system.

-   **Kernel Namespaces**: The decoding process is run in new PID, network, and mount namespaces. This means it has its own process tree, no network access, and a private filesystem view.
-   **`seccomp-bpf`**: A strict `seccomp-bpf` filter is applied to the decoding process, limiting the available system calls to only those that are absolutely necessary for decoding an image. Three different `seccomp` profiles are used: a general profile for PNG and JPEG decoding, a more restrictive profile for SVG decoding, and a profile for the Wasm runtime.
-   **Landlock**: A Landlock ruleset is applied to the decoding process, restricting its filesystem access to only the input file. This prevents a compromised decoder from accessing any other files on the system.

This sandboxing approach significantly reduces the attack surface and makes it much more difficult for a compromised decoder to have any impact on the host system.

## Audio Library Hardening

For detailed information about audio library hardening, including threat models, implementation details, and best practices, see the [Audio Hardening Guide](AUDIO_HARDENING.md).

Key highlights:
- **Pure Rust implementations** eliminate memory safety vulnerabilities
- **Strict validation** of file signatures, sample rates, channels, and duration
- **Real-time limits** prevent DoS attacks from malformed audio
- **Malware protection** against embedded payloads in audio metadata
- **Production-ready** for processing untrusted audio from messaging apps

Example use case:
```rust
// Safely process audio file from Telegram voice chat
let audio_data = std::fs::read("telegram_voice.mp3")?;

match decode_mp3(&audio_data) {
    Ok(decoded) => {
        println!("Safe: {} samples, {} Hz, {} channels",
            decoded.samples.len(),
            decoded.sample_rate,
            decoded.channels);
    }
    Err(e) => {
        eprintln!("Malicious or malformed file detected: {}", e);
        // Quarantine the file
    }
}
```

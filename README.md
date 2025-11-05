# ImageHarden

ImageHarden is a system for hardening image decoding libraries on Debian-based systems. It provides a set of scripts and a Rust library to build and use hardened versions of `libpng`, `libjpeg-turbo`, `librsvg`, and `ffmpeg`, reducing the risk of remote code execution vulnerabilities in image decoding.

## Features

-   **Compile-Time Hardening**: Builds `libpng` and `libjpeg-turbo` with a comprehensive set of hardening flags, including stack protectors, RELRO, PIE, and Control-Flow Enforcement Technology (CET).
-   **Strict Runtime Limits**: The provided Rust wrappers enforce strict limits on image dimensions, memory usage, and other critical parameters to prevent denial-of-service and other attacks.
-   **Fail-Closed Error Handling**: The library is designed to fail closed, meaning that any error during the decoding process will result in a clear and immediate failure, rather than continuing with potentially corrupted data.
-   **CI Fuzzing**: The project includes a continuous integration setup with `cargo-fuzz` to continuously test the hardened libraries and Rust wrappers for vulnerabilities.
-   **Safe Rust Wrappers**: The Rust library provides a safe, idiomatic API for decoding images, abstracting away the complexities of the underlying C libraries and their FFI.
-   **Kernel-Level Sandboxing**: The demonstration binary uses `seccomp-bpf`, kernel namespaces, and Landlock to create a secure, isolated environment for image decoding.
-   **SVG Sanitization**: SVG files are sanitized with `ammonia` to remove potentially malicious content before being rendered.
-   **FFmpeg Wasm Sandboxing**: FFmpeg is compiled to WebAssembly and run in a secure, sandboxed environment using the `wasmtime` runtime.

## Getting Started

### Prerequisites

-   A Debian-based system (e.g., Ubuntu) with a modern kernel (5.13+ for Landlock)
-   `build-essential`, `clang`, `cmake`, `nasm`, `autoconf`, `automake`, `libtool`, `git`, `pkg-config`, `librsvg2-dev`
-   The Rust toolchain

### Building the Hardened Libraries

The `build.sh` script automates the process of downloading, compiling, and installing the hardened versions of `libpng` and `libjpeg-turbo`.

```bash
./build.sh
```

This script will install the necessary dependencies, clone the library source code, and build the libraries with the hardening flags specified in `mission.md`.

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

The `image_harden` Rust library provides four main functions for decoding media: `decode_png`, `decode_jpeg`, `decode_svg`, and `decode_video`. These functions take a byte slice of the media data and return a `Result` containing either the decoded data or an `ImageHardenError`.

To use the library, add it as a dependency to your `Cargo.toml`:

```toml
[dependencies]
image_harden = { path = "./image_harden" }
```

Then, you can use the functions as follows:

```rust
use image_harden::{decode_video, ImageHardenError};
use std::fs::File;
use std::io::Read;

fn main() -> Result<(), ImageHardenError> {
    let mut file = File::open("my_video.mp4")?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)?;

    let decoded_video = decode_video(&buffer)?;

    println!("Successfully decoded video with size: {}", decoded_video.len());

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

The project is set up with `cargo-fuzz` to allow for continuous fuzzing of the decoding functions. To run the fuzz tests:

```bash
cd image_harden
cargo fuzz run fuzz_png
cargo fuzz run fuzz_jpeg
```

The fuzz tests are also integrated into the CI pipeline and will run automatically on every push and pull request.

## Security

ImageHarden is designed to provide a secure-by-default image decoding solution. The combination of compile-time hardening, runtime limits, and continuous fuzzing provides a robust defense against a wide range of vulnerabilities.

### Sandboxing

The `image_harden_cli` demonstration binary uses a combination of kernel namespaces, `seccomp-bpf`, and Landlock to create a sandboxed environment for image decoding. This provides an additional layer of security by isolating the decoding process from the rest of the system.

-   **Kernel Namespaces**: The decoding process is run in new PID, network, and mount namespaces. This means it has its own process tree, no network access, and a private filesystem view.
-   **`seccomp-bpf`**: A strict `seccomp-bpf` filter is applied to the decoding process, limiting the available system calls to only those that are absolutely necessary for decoding an image. Three different `seccomp` profiles are used: a general profile for PNG and JPEG decoding, a more restrictive profile for SVG decoding, and a profile for the Wasm runtime.
-   **Landlock**: A Landlock ruleset is applied to the decoding process, restricting its filesystem access to only the input file. This prevents a compromised decoder from accessing any other files on the system.

This sandboxing approach significantly reduces the attack surface and makes it much more difficult for a compromised decoder to have any impact on the host system.

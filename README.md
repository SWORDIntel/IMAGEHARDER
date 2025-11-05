# ImageHarden

ImageHarden is a system for hardening image decoding libraries on Debian-based systems. It provides a set of scripts and a Rust library to build and use hardened versions of `libpng` and `libjpeg-turbo`, reducing the risk of remote code execution vulnerabilities in image decoding.

## Features

-   **Compile-Time Hardening**: Builds `libpng` and `libjpeg-turbo` with a comprehensive set of hardening flags, including stack protectors, RELRO, PIE, and Control-Flow Enforcement Technology (CET).
-   **Strict Runtime Limits**: The provided Rust wrappers enforce strict limits on image dimensions, memory usage, and other critical parameters to prevent denial-of-service and other attacks.
-   **Fail-Closed Error Handling**: The library is designed to fail closed, meaning that any error during the decoding process will result in a clear and immediate failure, rather than continuing with potentially corrupted data.
-   **CI Fuzzing**: The project includes a continuous integration setup with `cargo-fuzz` to continuously test the hardened libraries and Rust wrappers for vulnerabilities.
-   **Safe Rust Wrappers**: The Rust library provides a safe, idiomatic API for decoding images, abstracting away the complexities of the underlying C libraries and their FFI.

## Getting Started

### Prerequisites

-   A Debian-based system (e.g., Ubuntu)
-   `build-essential`, `clang`, `cmake`, `nasm`, `autoconf`, `automake`, `libtool`, `git`, `pkg-config`
-   The Rust toolchain

### Building the Hardened Libraries

The `build.sh` script automates the process of downloading, compiling, and installing the hardened versions of `libpng` and `libjpeg-turbo`.

```bash
./build.sh
```

This script will install the necessary dependencies, clone the library source code, and build the libraries with the hardening flags specified in `mission.md`.

### Using the Rust Library

The `image_harden` Rust library provides two main functions for decoding images: `decode_png` and `decode_jpeg`. These functions take a byte slice of the image data and return a `Result` containing either the decoded image data or an `ImageHardenError`.

To use the library, add it as a dependency to your `Cargo.toml`:

```toml
[dependencies]
image_harden = { path = "./image_harden" }
```

Then, you can use the functions as follows:

```rust
use image_harden::{decode_png, ImageHardenError};
use std::fs::File;
use std::io::Read;

fn main() -> Result<(), ImageHardenError> {
    let mut file = File::open("my_image.png")?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)?;

    let decoded_image = decode_png(&buffer)?;

    println!("Successfully decoded image with size: {}", decoded_image.len());

    Ok(())
}
```

### Running the Demonstration Binary

The project includes a demonstration binary, `image_harden_cli`, which can be used to test the library. To build and run the binary:

```bash
cd image_harden
cargo build
./target/debug/image_harden_cli /path/to/your/image.png
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

# IMAGEHARDER

Hardened media decoding stack that prioritizes safety, observability, and predictable integration. The repo is now organized for use as a Git submodule so parent projects can embed the `image_harden` crate and reuse the hardened build tooling.

## Highlights
- Defensive decoders for common image formats (PNG, JPEG, GIF, WebP, HEIC/HEIF, SVG) plus pure-Rust audio codecs (MP3, Vorbis, FLAC) and video container validation.
- Extended format modules (AVIF, JPEG XL, TIFF, OpenEXR, ICC/EXIF) are feature-gated for projects that need them.
- Runtime hardening: strict dimension/file limits, fail-closed error handling, sandboxed video validation, and optional Prometheus metrics server.
- Drop-in CLI (`image_harden_cli`) for local validation using the same code paths as the library.

## Quick start
```bash
# Clone as a standalone repo
git clone https://github.com/SWORDIntel/IMAGEHARDER.git

# or add as a submodule inside an existing project
git submodule add https://github.com/SWORDIntel/IMAGEHARDER.git external/imageharder
```

## Public API (library)
Add the crate to your workspace and call the hardened helpers directly:

```toml
# parent-project/Cargo.toml
[dependencies]
image_harden = { path = "external/imageharder/image_harden" }
```

```rust
use image_harden::decode_png;

fn decode(bytes: &[u8]) -> Result<Vec<u8>, image_harden::ImageHardenError> {
    decode_png(bytes)
}
```

See [`docs/INTEGRATION.md`](docs/INTEGRATION.md) for submodule workflow, feature flags, and metrics exposure.

## Building the CLI
```bash
cd image_harden
cargo build --release
```

## Repository layout
- `image_harden/` – Rust crate with the hardened decoders and CLI entrypoint.
- `docs/INTEGRATION.md` – concise guide for embedding as a submodule.
- `docs/archive/` – preserved deep-dives (build notes, platform guides, extended hardening writeups).
- `docs/HARDENING_LIBSODIUM.md` – exploratory notes on applying similar hardening patterns to libsodium.
- `config/`, `ffmpeg/`, `docker-compose.yml` – deployment aids retained for downstream integrators.

## Security
Security contacts and policy are tracked in [`SECURITY.md`](SECURITY.md). Runtime mitigations are enabled by default; feature flags in `image_harden/Cargo.toml` gate optional codecs.

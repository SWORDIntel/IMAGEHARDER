# Integration guide

This guide shows how to embed IMAGEHARDER as a Git submodule and call the hardened decoder API from a parent project.

## 1) Add the repository as a submodule
```bash
git submodule add https://github.com/SWORDIntel/IMAGEHARDER.git external/imageharder
git submodule update --init --recursive
```

## 2) Wire the crate into your workspace
Add the crate using a path dependency so the parent project builds against the submodule source.

```toml
# parent-project/Cargo.toml
[dependencies]
image_harden = { path = "external/imageharder/image_harden" }
```

If you keep a Cargo workspace, also append the crate to `members`:
```toml
[workspace]
members = [
  "image_harden",                # if IMAGEHARDER lives at repo root
  "external/imageharder/image_harden"
]
```

## 3) Call the public API
The `api` module exposes a minimal surface that wraps the internal decoders and feature-gated formats.

```rust
use image_harden::api::{DecodedMedia, HardenedDecoder, MediaFormat};

fn decode_png(bytes: &[u8]) -> Result<DecodedMedia, image_harden::ImageHardenError> {
    HardenedDecoder::decode(MediaFormat::Png, bytes)
}
```

You can check what is currently compiled in (based on enabled features) at runtime:
```rust
let advertised = image_harden::api::supported_formats();
assert!(advertised.contains(&"png"));
```

## 4) Feature flags
Optional formats are disabled by default to keep builds lean. Enable only what you need in the dependency declaration:

```toml
[dependencies]
image_harden = { path = "external/imageharder/image_harden", features = ["avif", "jxl", "tiff", "openexr", "icc", "exif"] }
```

## 5) Metrics (optional)
The crate ships a tiny Prometheus exporter to surface decode metrics.

```rust
// Expose metrics on 0.0.0.0:9898
image_harden::metrics_server::start_metrics_server("0.0.0.0:9898")?;
```

## 6) Updating the submodule
Pull upstream changes and propagate to your workspace:
```bash
git submodule update --remote external/imageharder
cd external/imageharder && git checkout <tag-or-commit>
```

## Notes for Xen domU/CI builders
- The build is pure Rust by default; C-based optional codecs (e.g., libavif) require system headers and are isolated behind feature flags.
- The CLI entrypoint (`image_harden_cli`) exercises the same hardened limits as the library for parity testing.

# Additional Media Formats Guide

## Potentially Useful Format Extensions

While the core hardening covers the most common attack vectors, here are additional formats you might want to add based on your threat model:

### Images

#### WebP Support (Modern Web Format)
```toml
# Add to image_harden/Cargo.toml
webp = "0.2"
```

```rust
// Add to image_harden/src/lib.rs
pub fn decode_webp(data: &[u8]) -> Result<Vec<u8>, ImageHardenError> {
    use webp::Decoder;

    // Validate WebP signature
    if data.len() < 12 || &data[0..4] != b"RIFF" || &data[8..12] != b"WEBP" {
        return Err(ImageHardenError::WebPError("Invalid WebP signature".to_string()));
    }

    let decoder = Decoder::new(data);
    let decoded = decoder.decode()
        .ok_or_else(|| ImageHardenError::WebPError("Decoding failed".to_string()))?;

    Ok(decoded.to_owned())
}
```

**Rationale**: WebP is increasingly common on the web and has had security vulnerabilities (CVE-2023-4863).

#### AVIF Support (Next-Gen Format)
```toml
ravif = "0.11"
libavif = "0.13"
```

**Rationale**: AVIF is the successor to WebP, uses AV1 encoding, requires careful validation.

#### HEIF/HEIC Support (Apple)
**Rationale**: iOS/macOS default format, contains complex codec chains, HIGH RISK.
**Recommendation**: Use hardened libheif or pure Rust parser (in development).

### Audio

#### AAC Support (Very Common)
```toml
# AAC is typically in MP4 containers
# Already handled by mp4parse + FFmpeg-Wasm
```

**Note**: AAC decoding is covered by video hardening (MP4 container).

#### ALAC (Apple Lossless)
```toml
alac = "0.1"  # If pure Rust implementation exists
```

**Rationale**: Also in MP4 containers, less common, Apple ecosystem.

#### Speex (VoIP)
**Rationale**: Legacy VoIP codec, largely replaced by Opus. Low priority.

#### AMR (Mobile)
**Rationale**: Mobile codec (3GPP), HIGH RISK in mobile environments.
**Recommendation**: Add if processing mobile uploads.

### Video

#### FLV (Flash Video) - DEPRECATED
**Rationale**: Legacy Flash format, EXTREMELY VULNERABLE.
**Recommendation**: **REJECT AT FIREWALL** - Do not process FLV files in production.

```rust
// Example: Reject FLV immediately
pub fn validate_video_container(data: &[u8]) -> Result<VideoMetadata, ImageHardenError> {
    // Check for FLV signature
    if data.len() >= 3 && &data[0..3] == b"FLV" {
        return Err(ImageHardenError::VideoValidationError(
            "FLV format is deprecated and insecure - REJECTED".to_string()
        ));
    }
    // ... rest of validation
}
```

#### MPEG-TS (Transport Stream)
**Use Case**: Broadcasting, IPTV, live streaming.
**Complexity**: HIGH - requires different parser architecture (packet-based).

```toml
# If needed, add MPEG-TS parser
mpeg-ts = "0.1"  # Check for pure Rust implementation
```

**Implementation Effort**: HIGH - requires streaming validation, different from container parsing.

#### 3GP/3GPP (Mobile)
**Note**: 3GP is a subset of MP4, already handled by mp4parse.

```rust
// 3GP detection (already works with MP4 parser)
// File signature: 3gp5, 3gp4, 3ge6, etc. in ftyp box
```

### Documents (If Processing Mixed Media)

#### PDF with Embedded Media
**EXTREME RISK**: PDFs can embed JavaScript, videos, Flash.
**Recommendation**: Use separate PDF hardening (not included here).

#### Microsoft Office (DOCX, PPTX) with Media
**RISK**: OLE/ZIP containers with embedded videos/audio.
**Recommendation**: Extract media, validate separately.

## Format Risk Assessment

| Format | Risk Level | Attack Surface | Recommendation |
|--------|-----------|----------------|----------------|
| WebP | HIGH | Codec vulnerabilities (CVE-2023-4863) | **Implement** |
| AVIF | MEDIUM-HIGH | New format, AV1 complexity | **Monitor** CVEs |
| HEIF/HEIC | HIGH | Complex codec chain, Apple | **Implement** if iOS uploads |
| AAC | MEDIUM | In MP4 containers | **Already covered** |
| FLV | CRITICAL | Legacy, Flash-related | **REJECT** |
| MPEG-TS | MEDIUM | Broadcasting, streaming | **Add** if needed |
| AMR | MEDIUM-HIGH | Mobile uploads | **Add** if mobile-heavy |

## Quick Add: WebP Support (Recommended)

Since WebP is common and had a recent critical CVE (CVE-2023-4863), here's a quick implementation:

```bash
# 1. Add to Cargo.toml
cd image_harden
cargo add webp

# 2. Add decoder function to src/lib.rs (see above)

# 3. Add error variant
#[error("WebP decoding failed: {0}")]
WebPError(String),

# 4. Add fuzz target
cat > fuzz/fuzz_targets/fuzz_webp.rs <<'EOF'
#![no_main]
use libfuzzer_sys::fuzz_target;
use image_harden::decode_webp;

fuzz_target!(|data: &[u8]| {
    let _ = decode_webp(data);
});
EOF

# 5. Add to fuzz/Cargo.toml
# [[bin]]
# name = "fuzz_webp"
# path = "fuzz_targets/fuzz_webp.rs"

# 6. Update documentation
```

## Quick Add: HEIF/HEIC Support (For iOS)

```toml
# Cargo.toml
libheif-sys = "1.14"  # Bindings to C library (or pure Rust if available)
```

```rust
// Hardened HEIF decoder
pub fn decode_heif(data: &[u8]) -> Result<Vec<u8>, ImageHardenError> {
    // Validate HEIF signature
    if data.len() < 12 || &data[4..8] != b"ftyp" {
        return Err(ImageHardenError::HeifError("Invalid HEIF signature".to_string()));
    }

    // Check for Apple brand codes (heic, heix, mif1, etc.)
    let brand = &data[8..12];
    if brand != b"heic" && brand != b"heix" && brand != b"mif1" {
        return Err(ImageHardenError::HeifError("Unsupported HEIF brand".to_string()));
    }

    // Use libheif with strict validation
    // ... implementation ...
}
```

## Format Prioritization for Your Use Case

### High Priority (Add Now):
1. **WebP** - Common, recent CVEs, HIGH RISK
2. **HEIF/HEIC** - If you handle iOS/macOS uploads

### Medium Priority (Consider):
3. **MPEG-TS** - If you do live streaming
4. **AMR** - If you have mobile users
5. **AVIF** - Future-proofing

### Low Priority (Skip Unless Needed):
6. Speex - Replaced by Opus
7. ALAC - Niche, Apple only
8. WavPack - Rare

### NEVER Implement (Reject at Firewall):
- **FLV** - Flash is dead, EXTREME RISK
- **SWF** - Flash, EXTREME RISK
- **HTA** - HTML Application, malware vector

## Testing New Formats

```bash
# For each new format added:

# 1. Create fuzz target
cargo fuzz run fuzz_webp -- -max_total_time=3600

# 2. Generate test corpus
mkdir -p corpus/webp
# Add 100+ valid WebP files
# Add 100+ malformed WebP files from fuzzing

# 3. Run CVE reproduction tests
# Search: "WebP CVE POC" on GitHub
# Test known CVEs to ensure hardening works

# 4. Benchmark performance
cargo bench webp_decode

# 5. Update documentation
echo "WebP: ✅ Implemented" >> SECURITY_ARCHITECTURE.md
```

## Container Format Cheat Sheet

| Extension | Container | Codecs | Parser | Status |
|-----------|-----------|--------|--------|--------|
| .mp4 | MP4 | H.264, AAC | mp4parse | ✅ |
| .mov | MP4 | Various | mp4parse | ✅ |
| .mkv | Matroska | Various | matroska | ✅ |
| .webm | Matroska | VP8/VP9 | matroska | ✅ |
| .avi | RIFF AVI | Various | custom | ✅ |
| .flv | FLV | H.263, MP3 | REJECT | ❌ |
| .ts | MPEG-TS | H.264 | TODO | ⏳ |
| .3gp | MP4 | H.263, AMR | mp4parse | ✅ |
| .m4a | MP4 | AAC, ALAC | mp4parse | ✅ |

## Conclusion

For most use cases, the **current implementation is sufficient**. Add WebP if you process web images, HEIF if you handle iOS uploads. Everything else is niche or legacy.

**When in doubt**: REJECT unknown formats at the firewall. Better to be conservative.

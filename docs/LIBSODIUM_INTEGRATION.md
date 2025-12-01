# Libsodium Integration for IMAGEHARDER

## Overview

Libsodium is a modern, easy-to-use software library for encryption, decryption, signatures, password hashing, and more. It provides high-quality cryptographic primitives with a simple API.

## Use Cases for IMAGEHARDER

### 1. **Media File Integrity (Digital Signatures)**
- Sign decoded media files to verify provenance
- Verify media signatures before processing
- Ed25519 signatures (fast, secure, small)
- Use case: Ensure media files haven't been tampered with

### 2. **Authenticated Encryption**
- Encrypt sensitive media files with authentication
- ChaCha20-Poly1305 AEAD (faster than AES on CPUs without AES-NI)
- Use case: Protect confidential images/videos at rest

### 3. **Secure Key Derivation**
- Argon2id password hashing (memory-hard, side-channel resistant)
- Key derivation from master keys
- Use case: Generate encryption keys from user passwords

### 4. **Memory Protection**
- Lock sensitive memory pages (prevent swapping)
- Secure memory zeroing (prevent data leakage)
- Use case: Protect decoded media buffers containing sensitive data

### 5. **Sealed Boxes (Anonymous Encryption)**
- Encrypt without sender authentication
- Ephemeral key pairs
- Use case: Submit encrypted media without revealing sender identity

### 6. **Cryptographically Secure RNG**
- Generate secure random numbers
- Better than system RNG for security-critical operations
- Use case: Generate IVs, nonces, keys

## Proposed Architecture

```
IMAGEHARDER/
├── libsodium/              # Submodule (official libsodium)
├── image_harden/
│   ├── src/
│   │   ├── crypto/         # New crypto module
│   │   │   ├── mod.rs
│   │   │   ├── sign.rs     # Ed25519 signatures
│   │   │   ├── encrypt.rs  # Authenticated encryption
│   │   │   ├── derive.rs   # Key derivation
│   │   │   └── secure.rs   # Secure memory operations
│   │   └── ...
│   └── ...
└── build_crypto.sh         # Build libsodium with hardening
```

## Integration Plan

### Phase 1: Basic Integration
- Add libsodium submodule
- Build with Meteor Lake optimizations
- Rust FFI bindings (use existing `libsodium-sys` crate)
- Basic signing/verification

### Phase 2: Core Features
- File signing and verification
- Authenticated encryption/decryption
- Key derivation functions
- Secure memory operations

### Phase 3: Advanced Features
- Sealed boxes for anonymous encryption
- Stream encryption for large files
- Public key infrastructure (PKI) integration
- Hardware acceleration (AES-NI, SHA-NI where available)

## Security Considerations

### Hardening Flags
Apply same hardening as other libraries:
- Stack protection
- FORTIFY_SOURCE=3
- RELRO + PIE
- Control flow integrity

### CPU Optimization
- Meteor Lake: Use AVX2, AES-NI, SHA extensions
- Libsodium has optimized implementations for:
  - ChaCha20: AVX2
  - Poly1305: AVX2
  - SHA-512: SHA extensions
  - Ed25519: AVX2

### Memory Safety
- Use libsodium's secure memory functions
- Lock sensitive pages to prevent swapping
- Secure zeroing of buffers
- Guard pages around sensitive allocations

## Example Usage

### File Signing
```rust
use image_harden::crypto::sign;

// Generate keypair
let (public_key, secret_key) = sign::generate_keypair()?;

// Sign decoded image
let image_data = decode_png(&input)?;
let signature = sign::sign(&image_data, &secret_key)?;

// Verify signature
if sign::verify(&image_data, &signature, &public_key)? {
    println!("Image signature valid");
}
```

### Authenticated Encryption
```rust
use image_harden::crypto::encrypt;

// Derive key from password
let key = encrypt::derive_key("user_password", "salt")?;

// Encrypt image
let image_data = decode_jpeg(&input)?;
let encrypted = encrypt::encrypt_aead(&image_data, &key)?;

// Decrypt image
let decrypted = encrypt::decrypt_aead(&encrypted, &key)?;
```

### Secure Memory
```rust
use image_harden::crypto::secure;

// Allocate secure memory for sensitive data
let mut sensitive_buffer = secure::allocate_locked(1024)?;

// Use buffer...
// Process sensitive image data

// Securely zero and free
secure::free_locked(sensitive_buffer)?;
```

## Performance Impact

### ChaCha20-Poly1305 (Meteor Lake)
- **Encryption**: ~4-6 GB/s (AVX2)
- **Decryption**: ~4-6 GB/s (AVX2)
- **Overhead**: ~5-10% vs no encryption

### Ed25519 Signatures
- **Sign**: ~15,000 ops/sec
- **Verify**: ~5,000 ops/sec
- **Overhead**: Negligible for file-level operations

### Argon2id Key Derivation
- **Cost**: Configurable (memory-hard)
- **Typical**: 100-500ms per derivation
- **Use**: One-time at session start

## Libsodium Build

### Meteor Lake Optimizations
```bash
export IMAGEHARDEN_CPU=host
./build_crypto.sh

# Enables:
# - AVX2 for ChaCha20/Poly1305
# - AES-NI for AES-GCM fallback
# - SHA extensions for SHA-512
```

### Build Flags
```makefile
CFLAGS = $(HARDEN_CFLAGS)
  --enable-minimal         # Minimal build (only needed primitives)
  --disable-ssp            # We apply our own stack protection
  --enable-opt             # Enable CPU optimizations
```

## Comparison: AES-GCM vs ChaCha20-Poly1305

| Feature | AES-GCM | ChaCha20-Poly1305 |
|---------|---------|-------------------|
| **Speed (no AES-NI)** | Slow | Fast |
| **Speed (AES-NI)** | Very Fast | Fast |
| **Side-channel resistance** | Moderate | High |
| **Hardware support** | x86, ARM | Software only |
| **Recommended for** | CPUs with AES-NI | General purpose |

**For Meteor Lake**: Both are fast, but ChaCha20-Poly1305 provides better side-channel resistance.

## Integration with Existing Features

### ICC Profile Verification
```rust
// Sign ICC profile after validation
let icc_data = icc::validate_icc_profile(&profile)?;
let signature = sign::sign(&icc_data, &signing_key)?;
```

### EXIF Privacy Enhancement
```rust
// Encrypt EXIF before storage (preserve privacy)
let exif_data = exif::validate_exif(&raw_exif)?;
let encrypted_exif = encrypt::encrypt_aead(&exif_data, &user_key)?;
```

### Secure Decode Pipeline
```rust
// Lock decoded buffer in memory
let mut secure_buffer = secure::allocate_locked(width * height * 4)?;
decode_png_into_buffer(&input, &mut secure_buffer)?;
// Process without swapping to disk
```

## Dependencies

### Rust Crates
```toml
[dependencies]
libsodium-sys = "0.2"       # Low-level FFI bindings
sodiumoxide = "0.2"         # High-level Rust wrapper (optional)
# Or use libsodium-sys directly for better control
```

### System Libraries
- libsodium >= 1.0.18 (stable)
- Built from source with hardening flags

## Testing Strategy

### Unit Tests
- Key generation and serialization
- Sign/verify round-trips
- Encrypt/decrypt round-trips
- Secure memory operations

### Fuzz Tests
- Malformed signatures
- Invalid ciphertext
- Key derivation edge cases
- Memory corruption attempts

### Performance Tests
- Benchmark encryption/decryption speeds
- Compare AES-GCM vs ChaCha20-Poly1305
- Memory locking overhead

## Documentation

- `docs/CRYPTO_INTEGRATION.md` - Detailed crypto guide
- `image_harden/src/crypto/README.md` - API documentation
- Examples in `examples/crypto_demo.rs`

## Security Audit Considerations

When integrating cryptography:
1. **Don't roll your own crypto** - Use libsodium's primitives
2. **Proper key management** - Never hardcode keys
3. **Use high-level APIs** - Prefer sodiumoxide over libsodium-sys
4. **Constant-time operations** - Libsodium handles this
5. **Secure memory** - Use libsodium's memory protection
6. **Regular updates** - Keep libsodium up to date

## Timeline

- **Week 1**: Submodule integration + basic FFI
- **Week 2**: Core features (sign, encrypt, derive)
- **Week 3**: Integration with existing formats
- **Week 4**: Testing, fuzzing, documentation

## Open Questions

1. Should we use `sodiumoxide` (high-level) or `libsodium-sys` (low-level)?
   - **Recommendation**: Start with `sodiumoxide` for safety, drop to `libsodium-sys` if needed

2. Which encryption should be default: AES-GCM or ChaCha20-Poly1305?
   - **Recommendation**: ChaCha20-Poly1305 (better side-channel resistance)

3. Should encryption be opt-in or opt-out?
   - **Recommendation**: Opt-in (no encryption by default, but available)

4. How to manage keys? (environment variables, keyring, files?)
   - **Recommendation**: Multiple backends (env vars for dev, keyring for production)

## Conclusion

Libsodium integration would provide:
- **Enhanced security**: Cryptographic verification and encryption
- **Privacy features**: Secure memory, encrypted metadata
- **Performance**: Optimized for Meteor Lake (AVX2, AES-NI)
- **Ease of use**: Simple API, well-documented

This aligns perfectly with IMAGEHARDER's security-first approach.

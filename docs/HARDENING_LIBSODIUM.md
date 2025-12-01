# Applying IMAGEHARDER-style hardening to libsodium

The same practices used in IMAGEHARDER (bounded inputs, explicit error mapping, metrics, and sandboxing) can be mirrored when embedding
[libsodium](https://github.com/jedisct1/libsodium) for cryptographic workloads. This note outlines a secure-integration profile
suitable for Xen domU/CI builders.

## Goals
- Stable, minimal FFI boundary with explicit error types.
- Deterministic builds that pin versions and compiler flags.
- Isolation of key material and misuse-resistant APIs.
- Observability: metrics, tamper-evident audit logs, and build provenance.

## Build strategy
- **Version pinning**: vendor a known-good libsodium release and verify with `sha256sum` before build.
- **Compiler flags**: prefer `-fstack-protector-strong -D_FORTIFY_SOURCE=3 -fPIC -O2 -pipe -fno-plt` plus
  `-fstack-clash-protection` on supported toolchains. Enable `-fcf-protection=full` for CET-capable targets.
- **Linking**: prefer static linking in minimal domU images; use `RUSTFLAGS="-C target-feature=+crt-static"` when pairing with
  Rust consumers to avoid dynamic search-path issues.
- **Reproducibility**: capture build metadata (compiler, flags, git SHA) in an SBOM; wire `generate-sbom.sh` as part of CI.

## FFI surface design
- Wrap each libsodium primitive in narrow functions that accept length-checked slices and return `Result<Output, CryptoError>`.
- Prohibit raw pointer exposure; translate C error codes into typed Rust errors with context.
- Add zeroization hooks (`zeroize::Zeroize`) for buffers that carry keys, nonces, or secrets.
- Enforce domain separation by tagging APIs per purpose (e.g., `Auth`, `Aead`, `Kdf`) to discourage misuse.

## Runtime safeguards
- **Initialization guard**: perform a one-time `sodium_init()` with failure handling before exposing any primitive.
- **Key lifecycle**: keep keys in guarded memory (e.g., `secrecy::SecretVec`) and avoid serialization. Provide key-generation
  helpers that default to high-entropy RNGs (libsodium already defaults to `randombytes_buf`), and expose optional hardware RNG
  seeding for dom0/domU if available.
- **Parameter validation**: validate nonce sizes, tag lengths, and buffer boundaries before calling into libsodium.
- **Constant-time expectations**: document which APIs are constant-time and block callers from using them for unrelated purposes
  (e.g., no generic equality on MACs without constant-time compare).

## Observability and policy
- Emit Prometheus counters for successes/failures per primitive (without leaking secrets) and gauge unexpected parameter
  rejections.
- Capture audit logs that include operation type, key identifier, and policy decisions; ship logs over mTLS to central storage.
- Include a policy module that enforces approved cipher suites (e.g., `xchacha20poly1305_ietf`) and blocks deprecated ones.

## Testing and validation
- **KATs**: integrate libsodium's known-answer tests and add fuzzers around the FFI boundary to catch length/parameter issues.
- **Memory checks**: run under `valgrind`/`ASan` in CI; ensure zeroization paths are covered.
- **Cross-platform**: validate builds under Xen domU, containers, and bare-metal to confirm consistent instruction sets and
  `RDRAND` availability.

## Example integration sketch

```rust
// Pseudocode illustrating a narrow AEAD wrapper
pub fn seal(key: &SecretVec<u8>, nonce: &[u8; crypto_aead_xchacha20poly1305_ietf_NPUBBYTES],
            aad: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, CryptoError> {
    if plaintext.len() > MAX_MESSAGE || aad.len() > MAX_AAD {
        return Err(CryptoError::InputTooLarge);
    }

    let mut ciphertext = vec![0u8; plaintext.len() + TAG_LEN];
    let mut clen = 0usize;
    let rc = unsafe {
        crypto_aead_xchacha20poly1305_ietf_encrypt(
            ciphertext.as_mut_ptr(),
            &mut clen,
            plaintext.as_ptr(),
            plaintext.len() as u64,
            aad.as_ptr(),
            aad.len() as u64,
            std::ptr::null(),
            nonce.as_ptr(),
            key.expose_secret().as_ptr(),
        )
    };

    if rc != 0 {
        return Err(CryptoError::EncryptionFailed);
    }

    ciphertext.truncate(clen);
    Ok(ciphertext)
}
```

## Operational checklist
- Verify SBOM provenance for each release and store alongside build artifacts.
- Rotate keys on a fixed schedule; enforce non-reuse of nonces via per-key counters.
- Run `cargo deny` (or equivalent) to flag transitive CVEs in Rust bindings.
- Add a chaos test that simulates allocator failures to ensure safe unwinding.

Following this pattern mirrors IMAGEHARDER's focus on bounded inputs, explicit error handling, and strong observability—adapted to the
cryptographic domain served by libsodium.

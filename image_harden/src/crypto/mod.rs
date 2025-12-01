///! Cryptographic operations for IMAGEHARDER
///!
///! This module provides cryptographic primitives for:
///! - Digital signatures (Ed25519)
///! - Authenticated encryption (ChaCha20-Poly1305, AES256-GCM)
///! - Key derivation (Argon2id, HKDF)
///! - Secure memory operations
///!
///! All operations use libsodium for security and performance.

// Submodules
#[cfg(feature = "crypto")]
pub mod sign;

#[cfg(feature = "crypto")]
pub mod encrypt;

#[cfg(feature = "crypto")]
pub mod derive;

#[cfg(feature = "crypto")]
pub mod secure;

// Re-exports for convenience
#[cfg(feature = "crypto")]
pub use sign::{generate_keypair, sign_data, verify_signature};

#[cfg(feature = "crypto")]
pub use encrypt::{encrypt_aead, decrypt_aead, EncryptionKey};

#[cfg(feature = "crypto")]
pub use derive::{derive_key_from_password, KeyDerivationParams};

#[cfg(feature = "crypto")]
pub use secure::{SecureBuffer, lock_memory, unlock_memory};

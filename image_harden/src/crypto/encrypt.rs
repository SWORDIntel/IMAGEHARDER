///! Authenticated encryption using ChaCha20-Poly1305
///!
///! Provides fast, secure AEAD (Authenticated Encryption with Associated Data):
///! - ChaCha20-Poly1305 (default, best side-channel resistance)
///! - AES256-GCM (alternative when AES-NI is available)

use crate::ImageHardenError;

/// Encryption key (32 bytes)
pub type EncryptionKey = [u8; 32];

/// Nonce for ChaCha20-Poly1305 (24 bytes for XChaCha20)
pub type Nonce = [u8; 24];

/// Authentication tag (16 bytes)
pub type Tag = [u8; 16];

/// Encrypted data with nonce and tag prepended
pub struct EncryptedData {
    pub nonce: Nonce,
    pub ciphertext: Vec<u8>,
    pub tag: Tag,
}

/// Generate a random encryption key
///
/// Uses cryptographically secure RNG from libsodium
pub fn generate_key() -> Result<EncryptionKey, ImageHardenError> {
    // TODO: Implement using libsodium randombytes_buf()
    Err(ImageHardenError::CryptoError(
        "Libsodium not yet integrated - run build_crypto.sh".to_string(),
    ))
}

/// Encrypt data using ChaCha20-Poly1305 AEAD
///
/// # Arguments
/// * `plaintext` - Data to encrypt
/// * `key` - 32-byte encryption key
/// * `associated_data` - Optional additional authenticated data (not encrypted)
///
/// # Returns
/// Encrypted data with nonce and authentication tag
///
/// # Example
/// ```
/// use image_harden::crypto::encrypt;
///
/// let key = encrypt::generate_key()?;
/// let encrypted = encrypt::encrypt_aead(&image_data, &key, None)?;
/// ```
pub fn encrypt_aead(
    plaintext: &[u8],
    key: &EncryptionKey,
    associated_data: Option<&[u8]>,
) -> Result<EncryptedData, ImageHardenError> {
    if plaintext.is_empty() {
        return Err(ImageHardenError::CryptoError(
            "Cannot encrypt empty data".to_string(),
        ));
    }

    // TODO: Implement using libsodium crypto_aead_xchacha20poly1305_ietf_encrypt()
    Err(ImageHardenError::CryptoError(
        "Libsodium not yet integrated - run build_crypto.sh".to_string(),
    ))
}

/// Decrypt data using ChaCha20-Poly1305 AEAD
///
/// # Arguments
/// * `encrypted` - Encrypted data with nonce and tag
/// * `key` - 32-byte encryption key
/// * `associated_data` - Optional additional authenticated data
///
/// # Returns
/// Decrypted plaintext if authentication succeeds
///
/// # Security
/// Returns error if:
/// - Authentication tag is invalid (data tampered)
/// - Nonce is incorrect
/// - Key is incorrect
///
/// # Example
/// ```
/// let decrypted = encrypt::decrypt_aead(&encrypted, &key, None)?;
/// ```
pub fn decrypt_aead(
    encrypted: &EncryptedData,
    key: &EncryptionKey,
    associated_data: Option<&[u8]>,
) -> Result<Vec<u8>, ImageHardenError> {
    if encrypted.ciphertext.is_empty() {
        return Err(ImageHardenError::CryptoError(
            "Cannot decrypt empty ciphertext".to_string(),
        ));
    }

    // TODO: Implement using libsodium crypto_aead_xchacha20poly1305_ietf_decrypt()
    Err(ImageHardenError::CryptoError(
        "Libsodium not yet integrated - run build_crypto.sh".to_string(),
    ))
}

/// Encrypt media file
///
/// Convenience function for encrypting decoded media
pub fn encrypt_media_file(
    media_data: &[u8],
    key: &EncryptionKey,
) -> Result<EncryptedData, ImageHardenError> {
    encrypt_aead(media_data, key, None)
}

/// Decrypt media file
///
/// Convenience function for decrypting media
pub fn decrypt_media_file(
    encrypted: &EncryptedData,
    key: &EncryptionKey,
) -> Result<Vec<u8>, ImageHardenError> {
    decrypt_aead(encrypted, key, None)
}

/// Serialize encrypted data to bytes
///
/// Format: nonce (24) || ciphertext (variable) || tag (16)
pub fn serialize_encrypted(encrypted: &EncryptedData) -> Vec<u8> {
    let mut result = Vec::with_capacity(24 + encrypted.ciphertext.len() + 16);
    result.extend_from_slice(&encrypted.nonce);
    result.extend_from_slice(&encrypted.ciphertext);
    result.extend_from_slice(&encrypted.tag);
    result
}

/// Deserialize encrypted data from bytes
///
/// Format: nonce (24) || ciphertext (variable) || tag (16)
pub fn deserialize_encrypted(data: &[u8]) -> Result<EncryptedData, ImageHardenError> {
    if data.len() < 40 {
        // minimum: nonce (24) + tag (16) = 40 bytes
        return Err(ImageHardenError::CryptoError(
            "Encrypted data too short".to_string(),
        ));
    }

    let mut nonce = [0u8; 24];
    nonce.copy_from_slice(&data[0..24]);

    let ciphertext = data[24..data.len() - 16].to_vec();

    let mut tag = [0u8; 16];
    tag.copy_from_slice(&data[data.len() - 16..]);

    Ok(EncryptedData {
        nonce,
        ciphertext,
        tag,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[ignore] // Requires libsodium
    fn test_key_generation() {
        let result = generate_key();
        // Will fail until libsodium is integrated
        assert!(result.is_err());
    }

    #[test]
    fn test_empty_encrypt() {
        let key = [0u8; 32];
        let result = encrypt_aead(&[], &key, None);
        assert!(result.is_err());
    }

    #[test]
    fn test_serialize_deserialize() {
        let encrypted = EncryptedData {
            nonce: [1u8; 24],
            ciphertext: vec![2u8; 100],
            tag: [3u8; 16],
        };

        let serialized = serialize_encrypted(&encrypted);
        assert_eq!(serialized.len(), 24 + 100 + 16);

        let deserialized = deserialize_encrypted(&serialized).unwrap();
        assert_eq!(deserialized.nonce, encrypted.nonce);
        assert_eq!(deserialized.ciphertext, encrypted.ciphertext);
        assert_eq!(deserialized.tag, encrypted.tag);
    }

    #[test]
    fn test_deserialize_too_short() {
        let result = deserialize_encrypted(&[0u8; 30]);
        assert!(result.is_err());
    }
}

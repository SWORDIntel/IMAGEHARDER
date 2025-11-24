///! ICC Color Profile handling with comprehensive hardening
///!
///! Security measures:
///! - Strict profile size limits (max 2 MB)
///! - Tag count validation
///! - Version validation
///! - Magic byte validation ('acsp')
///! - Strip profiles by default in hardened mode
///! - Fail-closed error handling

use crate::ImageHardenError;

/// Maximum allowed ICC profile size (2 MB)
const MAX_PROFILE_SIZE: usize = 2 * 1024 * 1024;

/// Maximum number of tags in profile
const MAX_TAG_COUNT: u32 = 256;

/// ICC profile magic signature 'acsp'
const ICC_MAGIC: &[u8] = b"acsp";

/// ICC profile magic offset in header
const ICC_MAGIC_OFFSET: usize = 36;

/// Hardened ICC profile configuration
#[derive(Debug, Clone)]
pub struct IccProfileConfig {
    pub max_profile_size: usize,
    pub max_tag_count: u32,
    pub strip_profiles: bool,
    pub strict_mode: bool,
}

impl Default for IccProfileConfig {
    fn default() -> Self {
        Self {
            max_profile_size: MAX_PROFILE_SIZE,
            max_tag_count: MAX_TAG_COUNT,
            strip_profiles: true, // Default: strip ICC profiles in hardened mode
            strict_mode: true,
        }
    }
}

/// ICC profile information
#[derive(Debug)]
pub struct IccProfile {
    pub version_major: u8,
    pub version_minor: u8,
    pub profile_size: u32,
    pub tag_count: u32,
}

/// Validate ICC profile
pub fn validate_icc_profile(data: &[u8]) -> Result<IccProfile, ImageHardenError> {
    validate_icc_profile_with_config(data, &IccProfileConfig::default())
}

/// Validate ICC profile with custom configuration
pub fn validate_icc_profile_with_config(
    data: &[u8],
    config: &IccProfileConfig,
) -> Result<IccProfile, ImageHardenError> {
    // Input validation
    if data.is_empty() {
        return Err(ImageHardenError::IccError(
            "Empty ICC profile data".to_string(),
        ));
    }

    // Size check
    if data.len() > config.max_profile_size {
        return Err(ImageHardenError::IccError(format!(
            "ICC profile size {} exceeds maximum {}",
            data.len(),
            config.max_profile_size
        )));
    }

    // Minimum size check (128 bytes for header)
    if data.len() < 128 {
        return Err(ImageHardenError::IccError(
            "ICC profile too small to be valid".to_string(),
        ));
    }

    // Profile size from header (first 4 bytes, big-endian)
    let profile_size = u32::from_be_bytes([data[0], data[1], data[2], data[3]]);

    if profile_size as usize != data.len() {
        return Err(ImageHardenError::IccError(format!(
            "ICC profile size mismatch: header says {}, actual {}",
            profile_size,
            data.len()
        )));
    }

    // Magic signature validation ('acsp' at offset 36)
    if data.len() < ICC_MAGIC_OFFSET + 4 {
        return Err(ImageHardenError::IccError(
            "ICC profile too small for magic signature".to_string(),
        ));
    }

    let magic = &data[ICC_MAGIC_OFFSET..ICC_MAGIC_OFFSET + 4];
    if magic != ICC_MAGIC {
        return Err(ImageHardenError::IccError(
            "Invalid ICC profile magic signature".to_string(),
        ));
    }

    // Version (bytes 8-9)
    let version_major = data[8];
    let version_minor = data[9];

    // Validate version (currently 2.x and 4.x are common)
    if version_major != 2 && version_major != 4 {
        if config.strict_mode {
            return Err(ImageHardenError::IccError(format!(
                "Unsupported ICC version: {}.{}",
                version_major, version_minor
            )));
        }
    }

    // Tag count (bytes 128-131, big-endian)
    if data.len() < 132 {
        return Err(ImageHardenError::IccError(
            "ICC profile too small for tag count".to_string(),
        ));
    }

    let tag_count = u32::from_be_bytes([data[128], data[129], data[130], data[131]]);

    if tag_count > config.max_tag_count {
        return Err(ImageHardenError::IccError(format!(
            "ICC profile tag count {} exceeds maximum {}",
            tag_count, config.max_tag_count
        )));
    }

    Ok(IccProfile {
        version_major,
        version_minor,
        profile_size,
        tag_count,
    })
}

/// Strip ICC profile from image data (default hardened mode behavior)
pub fn strip_icc_profile(_image_data: &[u8]) -> Result<Vec<u8>, ImageHardenError> {
    // TODO: Implement ICC profile stripping for various formats
    // This would parse format-specific containers and remove ICC chunks/tags:
    // - PNG: remove iCCP chunk
    // - JPEG: remove ICC_PROFILE APP2 segments
    // - TIFF: remove ICC profile tag
    // - WebP: remove ICCP chunk

    Err(ImageHardenError::IccError(
        "ICC profile stripping not yet implemented".to_string(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_profile() {
        let result = validate_icc_profile(&[]);
        assert!(result.is_err());
    }

    #[test]
    fn test_too_small_profile() {
        let result = validate_icc_profile(&[0u8; 100]);
        assert!(result.is_err());
    }

    #[test]
    fn test_invalid_magic() {
        let mut data = vec![0u8; 132];
        // Set size
        data[0..4].copy_from_slice(&132u32.to_be_bytes());
        // Wrong magic at offset 36
        data[36..40].copy_from_slice(b"xxxx");

        let result = validate_icc_profile(&data);
        assert!(result.is_err());
    }
}

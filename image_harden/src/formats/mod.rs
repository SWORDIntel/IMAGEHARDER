//! Extended format support modules
//!
//! This module provides hardened decoders for various image and metadata formats:
//! - AVIF (AV1 Image File Format)
//! - JPEG XL (next-gen lossy/lossless)
//! - TIFF (Tagged Image File Format)
//! - OpenEXR (HDR image format)
//! - ICC color profiles
//! - EXIF metadata

// Core formats (already in lib.rs)
// pub mod png;
// pub mod jpeg;
// pub mod gif;

// Extended formats
#[cfg(feature = "avif")]
pub mod avif;

#[cfg(feature = "jxl")]
pub mod jxl;

#[cfg(feature = "tiff")]
pub mod tiff;

#[cfg(feature = "openexr")]
pub mod exr;

// Hidden-path components
#[cfg(feature = "icc")]
pub mod icc;

#[cfg(feature = "exif")]
pub mod exif;

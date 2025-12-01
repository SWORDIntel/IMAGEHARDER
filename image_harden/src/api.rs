//! Public API surface for embedding IMAGEHARDER as a library.
//! This module wraps the individual decoders into a small, stable interface
//! that parent projects can depend on when the repository is consumed as a
//! Git submodule.

use crate::{
    decode_flac, decode_gif, decode_heif, decode_jpeg, decode_mp3, decode_png, decode_svg,
    decode_video, decode_vorbis, decode_webp, AudioData, ImageHardenError,
};

#[cfg(feature = "avif")]
use crate::formats::avif::decode_avif;
#[cfg(feature = "exif")]
use crate::formats::exif::validate_exif;
#[cfg(feature = "openexr")]
use crate::formats::exr::decode_exr;
#[cfg(feature = "icc")]
use crate::formats::icc::validate_icc_profile;
#[cfg(feature = "jxl")]
use crate::formats::jxl::decode_jxl;
#[cfg(feature = "tiff")]
use crate::formats::tiff::decode_tiff;

/// Supported media types for the unified decoder entrypoint.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaFormat {
    Png,
    Jpeg,
    Gif,
    WebP,
    Heif,
    Svg,
    #[cfg(feature = "avif")]
    Avif,
    #[cfg(feature = "jxl")]
    JpegXl,
    #[cfg(feature = "tiff")]
    Tiff,
    #[cfg(feature = "openexr")]
    OpenExr,
    AudioMp3,
    AudioVorbis,
    AudioFlac,
    VideoContainer,
}

/// Decoder output variants.
#[derive(Debug, Clone)]
pub enum DecodedMedia {
    Image(Vec<u8>),
    Audio(AudioData),
    Video(Vec<u8>),
}

/// Optional knobs for decoding. Currently only video uses an option
/// to specify the sandboxed WASM path.
#[derive(Debug, Default, Clone)]
pub struct DecoderOptions {
    pub video_wasm_path: Option<String>,
}

/// Convenience wrapper that exposes a minimal surface area for downstream
/// consumers. Use `decode` for sensible defaults or `decode_with_options` to
/// pass explicit configuration.
pub struct HardenedDecoder;

impl HardenedDecoder {
    /// Returns the crate version to make it easy to verify the linked build.
    pub fn version() -> &'static str {
        env!("CARGO_PKG_VERSION")
    }

    /// Decode using defaults.
    pub fn decode(format: MediaFormat, data: &[u8]) -> Result<DecodedMedia, ImageHardenError> {
        Self::decode_with_options(format, data, &DecoderOptions::default())
    }

    /// Decode with explicit options (e.g., WASM path for video validation).
    pub fn decode_with_options(
        format: MediaFormat,
        data: &[u8],
        options: &DecoderOptions,
    ) -> Result<DecodedMedia, ImageHardenError> {
        match format {
            MediaFormat::Png => decode_png(data).map(DecodedMedia::Image),
            MediaFormat::Jpeg => decode_jpeg(data).map(DecodedMedia::Image),
            MediaFormat::Gif => decode_gif(data).map(DecodedMedia::Image),
            MediaFormat::WebP => decode_webp(data).map(DecodedMedia::Image),
            MediaFormat::Heif => decode_heif(data).map(DecodedMedia::Image),
            MediaFormat::Svg => decode_svg(data).map(DecodedMedia::Image),
            #[cfg(feature = "avif")]
            MediaFormat::Avif => decode_avif(data).map(DecodedMedia::Image),
            #[cfg(feature = "jxl")]
            MediaFormat::JpegXl => decode_jxl(data).map(DecodedMedia::Image),
            #[cfg(feature = "tiff")]
            MediaFormat::Tiff => decode_tiff(data).map(DecodedMedia::Image),
            #[cfg(feature = "openexr")]
            MediaFormat::OpenExr => decode_exr(data).map(DecodedMedia::Image),
            MediaFormat::AudioMp3 => decode_mp3(data).map(DecodedMedia::Audio),
            MediaFormat::AudioVorbis => decode_vorbis(data).map(DecodedMedia::Audio),
            MediaFormat::AudioFlac => decode_flac(data).map(DecodedMedia::Audio),
            MediaFormat::VideoContainer => {
                decode_video(data, options.video_wasm_path.as_deref().unwrap_or(""))
                    .map(DecodedMedia::Video)
            }
        }
    }
}

/// Report which formats are available in the current build based on feature
/// flags. Useful for capability advertisement in parent applications.
pub fn supported_formats() -> Vec<&'static str> {
    let mut formats = vec![
        "png", "jpeg", "gif", "webp", "heif", "svg", "mp3", "vorbis", "flac", "video",
    ];

    #[cfg(feature = "avif")]
    {
        formats.push("avif");
    }
    #[cfg(feature = "jxl")]
    {
        formats.push("jpegxl");
    }
    #[cfg(feature = "tiff")]
    {
        formats.push("tiff");
    }
    #[cfg(feature = "openexr")]
    {
        formats.push("openexr");
    }
    #[cfg(feature = "icc")]
    {
        formats.push("icc");
    }
    #[cfg(feature = "exif")]
    {
        formats.push("exif");
    }

    formats
}

/// Validate metadata payloads without decoding image data.
#[cfg(any(feature = "icc", feature = "exif"))]
pub fn validate_metadata(data: &[u8]) -> Result<(), ImageHardenError> {
    #[cfg(feature = "icc")]
    {
        validate_icc_profile(data)?;
    }

    #[cfg(feature = "exif")]
    {
        validate_exif(data)?;
    }

    Ok(())
}

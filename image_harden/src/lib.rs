#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

use std::ffi::CStr;
use std::io::Read;
use std::mem;
use thiserror::Error;
use librsvg::SvgHandle;
use ammonia::clean;
use cairo;
use wasmtime::*;
use wasmtime_wasi::{WasiCtx, WasiCtxBuilder};

#[derive(Debug, Error)]
pub enum ImageHardenError {
    #[error("PNG decoding failed: {0}")]
    PngError(String),
    #[error("JPEG decoding failed: {0}")]
    JpegError(String),
    #[error("SVG decoding failed: {0}")]
    SvgError(String),
    #[error("Video decoding failed: {0}")]
    VideoError(String),
    #[error("Audio decoding failed: {0}")]
    AudioError(String),
    #[error("MP3 decoding failed: {0}")]
    Mp3Error(String),
    #[error("Vorbis decoding failed: {0}")]
    VorbisError(String),
    #[error("FLAC decoding failed: {0}")]
    FlacError(String),
    #[error("Opus decoding failed: {0}")]
    OpusError(String),
    #[error("Video container parsing failed: {0}")]
    VideoContainerError(String),
    #[error("Video validation failed: {0}")]
    VideoValidationError(String),
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Null pointer encountered")]
    NullPointer,
}

// PNG wrapper
pub fn decode_png(data: &[u8]) -> Result<Vec<u8>, ImageHardenError> {
    unsafe {
        let png_ptr = png_create_read_struct(
            PNG_LIBPNG_VER_STRING.as_ptr() as *const i8,
            std::ptr::null_mut(),
            Some(error_fn),
            Some(warning_fn),
        );
        if png_ptr.is_null() {
            return Err(ImageHardenError::NullPointer);
        }

        let info_ptr = png_create_info_struct(png_ptr);
        if info_ptr.is_null() {
            png_destroy_read_struct(&mut (png_ptr as png_structp), std::ptr::null_mut(), std::ptr::null_mut());
            return Err(ImageHardenError::NullPointer);
        }

        let jmp_buf_ptr = png_jmpbuf_wrapper(png_ptr) as *mut jmp_buf;
        if setjmp(mem::transmute(jmp_buf_ptr)) != 0 {
            png_destroy_read_struct(&mut (png_ptr as png_structp), &mut (info_ptr as png_infop), std::ptr::null_mut());
            return Err(ImageHardenError::PngError("PNG decoding failed".to_string()));
        }

        png_set_user_limits(png_ptr, 8192, 8192);
        png_set_chunk_cache_max(png_ptr, 128);
        png_set_chunk_malloc_max(png_ptr, 256 * 1024);

        let mut cursor = std::io::Cursor::new(data);
        png_set_read_fn(png_ptr, &mut cursor as *mut _ as png_voidp, Some(read_data_fn));

        png_read_info(png_ptr, info_ptr);

        let mut width: png_uint_32 = 0;
        let mut height: png_uint_32 = 0;
        let mut bit_depth: i32 = 0;
        let mut color_type: i32 = 0;

        png_get_IHDR(
            png_ptr,
            info_ptr,
            &mut width,
            &mut height,
            &mut bit_depth,
            &mut color_type,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        );

        png_set_expand(png_ptr);
        png_set_strip_16(png_ptr);
        png_set_gray_to_rgb(png_ptr);
        png_set_add_alpha(png_ptr, 0xff, PNG_FILLER_AFTER as i32);
        png_read_update_info(png_ptr, info_ptr);

        let row_bytes = png_get_rowbytes(png_ptr, info_ptr);
        let mut image_data = vec![0u8; row_bytes * height as usize];
        let mut row_pointers: Vec<png_bytep> = Vec::with_capacity(height as usize);
        for i in 0..height {
            row_pointers.push(image_data.as_mut_ptr().add(i as usize * row_bytes));
        }

        png_read_image(png_ptr, row_pointers.as_mut_ptr());

        png_destroy_read_struct(&mut (png_ptr as png_structp), &mut (info_ptr as png_infop), std::ptr::null_mut());

        Ok(image_data)
    }
}

// JPEG wrapper
struct JpegErrorManager {
    pub base: jpeg_error_mgr,
    pub jmp_buf: jmp_buf,
}

pub fn decode_jpeg(data: &[u8]) -> Result<Vec<u8>, ImageHardenError> {
    unsafe {
        let mut cinfo: jpeg_decompress_struct = std::mem::zeroed();
        let mut err_mgr = JpegErrorManager {
            base: std::mem::zeroed(),
            jmp_buf: std::mem::zeroed(),
        };

        cinfo.err = jpeg_std_error(&mut err_mgr.base);
        err_mgr.base.error_exit = Some(jpeg_error_exit);

        if setjmp(err_mgr.jmp_buf.as_mut_ptr()) != 0 {
            jpeg_destroy_decompress(&mut cinfo);
            return Err(ImageHardenError::JpegError("JPEG decoding failed".to_string()));
        }

        jpeg_CreateDecompress(&mut cinfo, JPEG_LIB_VERSION as i32, std::mem::size_of::<jpeg_decompress_struct>());

        (*cinfo.mem).max_memory_to_use = 64 * 1024 * 1024; // 64 MB
        for m in 0xE0..=0xEF {
            jpeg_save_markers(&mut cinfo, m, 0);
        }
        jpeg_save_markers(&mut cinfo, JPEG_COM as i32, 0);


        jpeg_mem_src(&mut cinfo, data.as_ptr(), data.len() as u64);

        jpeg_read_header(&mut cinfo, 1);

        if cinfo.image_width > 10000 || cinfo.image_height > 10000 {
            return Err(ImageHardenError::JpegError("Image dimensions exceed limits".to_string()));
        }
        cinfo.out_color_space = J_COLOR_SPACE_JCS_RGB;

        jpeg_start_decompress(&mut cinfo);

        let row_stride = cinfo.output_width as usize * cinfo.output_components as usize;
        let mut image_data = vec![0u8; row_stride * cinfo.output_height as usize];

        while cinfo.output_scanline < cinfo.output_height {
            let mut buffer = [image_data.as_mut_ptr().add(cinfo.output_scanline as usize * row_stride)];
            jpeg_read_scanlines(&mut cinfo, buffer.as_mut_ptr(), 1);
        }

        jpeg_finish_decompress(&mut cinfo);
        jpeg_destroy_decompress(&mut cinfo);

        Ok(image_data)
    }
}

// SVG wrapper
pub fn decode_svg(data: &[u8]) -> Result<Vec<u8>, ImageHardenError> {
    let sanitized_svg = clean(std::str::from_utf8(data).map_err(|e| ImageHardenError::SvgError(e.to_string()))?).to_string();
    let handle = SvgHandle::from_str(&sanitized_svg).map_err(|e| ImageHardenError::SvgError(e.to_string()))?;
    let mut surface = cairo::ImageSurface::create(cairo::Format::ARgb32, 256, 256).map_err(|e| ImageHardenError::SvgError(e.to_string()))?;
    let cr = cairo::Context::new(&mut surface).map_err(|e| ImageHardenError::SvgError(e.to_string()))?;
    handle.render_cairo(&cr).map_err(|e| ImageHardenError::SvgError(e.to_string()))?;
    let mut png_data = Vec::new();
    surface.write_to_png(&mut png_data).map_err(|e| ImageHardenError::SvgError(e.to_string()))?;
    Ok(png_data)
}

// Video wrapper
pub fn decode_video(data: &[u8], wasm_path: &str) -> Result<Vec<u8>, ImageHardenError> {
    // CRITICAL: Validate video BEFORE sending to FFmpeg to prevent VM escape
    validate_video_container(data)?;

    let engine = Engine::default();
    let mut linker = Linker::new(&engine);
    wasmtime_wasi::add_to_linker(&mut linker, |s| s).map_err(|e| ImageHardenError::VideoError(e.to_string()))?;

    let wasi = WasiCtxBuilder::new()
        .stdin(Box::new(wasmtime_wasi::pipe::ReadPipe::from_slice(data)))
        .stdout(Box::new(wasmtime_wasi::pipe::WritePipe::new_in_memory()))
        .inherit_stderr()
        .build();
    let mut store = Store::new(&engine, wasi);

    let module = Module::from_file(&engine, wasm_path).map_err(|e| ImageHardenError::VideoError(e.to_string()))?;
    linker
        .module(&mut store, "", &module)
        .map_err(|e| ImageHardenError::VideoError(e.to_string()))?;
    linker
        .get_default(&mut store, "")
        .map_err(|e| ImageHardenError::VideoError(e.to_string()))?
        .typed::<(), ()>(&store)
        .map_err(|e| ImageHardenError::VideoError(e.to_string()))?
        .call(&mut store, ())
        .map_err(|e| ImageHardenError::VideoError(e.to_string()))?;

    let mut stdout_buf = Vec::new();
    let mut stdout = store.data_mut().stdout().as_mut().ok_or_else(|| ImageHardenError::VideoError("Could not get stdout".to_string()))?;
    let mut stdout_clone = stdout.try_clone().map_err(|e| ImageHardenError::VideoError(e.to_string()))?;
    stdout_clone.read_to_end(&mut stdout_buf).map_err(|e| ImageHardenError::VideoError(e.to_string()))?;
    Ok(stdout_buf)
}


extern "C" fn error_fn(png_ptr: png_structp, error_msg: png_const_charp) {
    let msg = unsafe { CStr::from_ptr(error_msg).to_string_lossy().into_owned() };
    eprintln!("PNG error: {}", msg);
    unsafe { png_longjmp(png_ptr, 1) };
}

extern "C" fn warning_fn(_png_ptr: png_structp, warning_msg: png_const_charp) {
    let msg = unsafe { CStr::from_ptr(warning_msg).to_string_lossy().into_owned() };
    eprintln!("PNG warning: {}", msg);
}

unsafe extern "C" fn read_data_fn(png_ptr: png_structp, data: png_bytep, length: png_size_t) {
    let io_ptr = png_get_io_ptr(png_ptr);
    let cursor = &mut *(io_ptr as *mut std::io::Cursor<&[u8]>);
    let buffer = std::slice::from_raw_parts_mut(data, length);
    if cursor.read_exact(buffer).is_err() {
        png_error(png_ptr, "Read error".as_ptr() as *const i8);
    }
}

unsafe extern "C" fn jpeg_error_exit(cinfo: j_common_ptr) {
    let err_mgr = (*cinfo).err as *mut JpegErrorManager;
    longjmp((*err_mgr).jmp_buf.as_mut_ptr(), 1);
}

// ============================================================================
// AUDIO DECODING - PURE RUST IMPLEMENTATIONS
// ============================================================================
//
// Using pure Rust libraries provides memory safety guarantees and eliminates
// entire classes of vulnerabilities common in C audio codecs:
// - Buffer overflows
// - Use-after-free
// - Integer overflows
// - Uninitialized memory access
//
// These implementations are safe to use with untrusted input from sources
// like Telegram, Discord, email attachments, etc.

// Security limits for audio decoding
const MAX_AUDIO_FILE_SIZE: usize = 100 * 1024 * 1024;  // 100 MB
const MAX_AUDIO_DURATION_SECS: u64 = 600;              // 10 minutes
const MAX_SAMPLE_RATE: u32 = 192000;                   // 192 kHz
const MAX_CHANNELS: u16 = 8;                           // 8 channels

// Audio sample output format
#[derive(Debug, Clone)]
pub struct AudioData {
    pub samples: Vec<i16>,      // Interleaved samples
    pub sample_rate: u32,       // Hz
    pub channels: u16,          // 1=mono, 2=stereo, etc.
    pub duration_secs: f64,     // Total duration
}

// MP3 decoder (using minimp3 - Rust wrapper around C minimp3)
// minimp3 is a minimal, well-audited MP3 decoder
pub fn decode_mp3(data: &[u8]) -> Result<AudioData, ImageHardenError> {
    use minimp3::{Decoder, Frame};

    // Validate input size
    if data.len() > MAX_AUDIO_FILE_SIZE {
        return Err(ImageHardenError::Mp3Error(
            format!("File too large: {} bytes (max: {})", data.len(), MAX_AUDIO_FILE_SIZE)
        ));
    }

    // Validate MP3 signature (MPEG frame sync)
    if data.len() < 2 || (data[0] != 0xFF || (data[1] & 0xE0) != 0xE0) {
        return Err(ImageHardenError::Mp3Error("Invalid MP3 signature".to_string()));
    }

    let mut decoder = Decoder::new(data);
    let mut all_samples = Vec::new();
    let mut sample_rate = 0u32;
    let mut channels = 0u16;
    let mut total_samples = 0usize;

    loop {
        match decoder.next_frame() {
            Ok(Frame { data: samples, sample_rate: rate, channels: ch, .. }) => {
                // Validate audio parameters
                if rate > MAX_SAMPLE_RATE {
                    return Err(ImageHardenError::Mp3Error(
                        format!("Sample rate too high: {} Hz", rate)
                    ));
                }
                if ch as u16 > MAX_CHANNELS {
                    return Err(ImageHardenError::Mp3Error(
                        format!("Too many channels: {}", ch)
                    ));
                }

                // Set format from first frame
                if sample_rate == 0 {
                    sample_rate = rate as u32;
                    channels = ch as u16;
                }

                // Check duration limit
                total_samples += samples.len();
                let duration_secs = total_samples as u64 / (sample_rate as u64 * channels as u64);
                if duration_secs > MAX_AUDIO_DURATION_SECS {
                    return Err(ImageHardenError::Mp3Error(
                        format!("Audio too long: {} seconds (max: {})", duration_secs, MAX_AUDIO_DURATION_SECS)
                    ));
                }

                all_samples.extend_from_slice(&samples);
            }
            Err(minimp3::Error::Eof) => break,
            Err(e) => return Err(ImageHardenError::Mp3Error(format!("Decode error: {:?}", e))),
        }
    }

    if all_samples.is_empty() {
        return Err(ImageHardenError::Mp3Error("No audio data decoded".to_string()));
    }

    let duration_secs = all_samples.len() as f64 / (sample_rate as f64 * channels as f64);

    Ok(AudioData {
        samples: all_samples,
        sample_rate,
        channels,
        duration_secs,
    })
}

// Vorbis decoder (using lewton - pure Rust implementation)
pub fn decode_vorbis(data: &[u8]) -> Result<AudioData, ImageHardenError> {
    use lewton::inside_ogg::OggStreamReader;

    // Validate input size
    if data.len() > MAX_AUDIO_FILE_SIZE {
        return Err(ImageHardenError::VorbisError(
            format!("File too large: {} bytes", data.len())
        ));
    }

    // Validate Ogg signature
    if data.len() < 4 || &data[0..4] != b"OggS" {
        return Err(ImageHardenError::VorbisError("Invalid Ogg signature".to_string()));
    }

    let cursor = std::io::Cursor::new(data);
    let mut reader = OggStreamReader::new(cursor)
        .map_err(|e| ImageHardenError::VorbisError(format!("Failed to initialize reader: {:?}", e)))?;

    // Validate audio parameters
    let sample_rate = reader.ident_hdr.audio_sample_rate;
    let channels = reader.ident_hdr.audio_channels as u16;

    if sample_rate > MAX_SAMPLE_RATE {
        return Err(ImageHardenError::VorbisError(
            format!("Sample rate too high: {} Hz", sample_rate)
        ));
    }
    if channels > MAX_CHANNELS {
        return Err(ImageHardenError::VorbisError(
            format!("Too many channels: {}", channels)
        ));
    }

    let mut all_samples = Vec::new();
    let mut total_samples = 0usize;

    while let Some(packet) = reader.read_dec_packet_itl()
        .map_err(|e| ImageHardenError::VorbisError(format!("Decode error: {:?}", e)))? {

        total_samples += packet.len();

        // Check duration limit
        let duration_secs = total_samples as u64 / (sample_rate as u64 * channels as u64);
        if duration_secs > MAX_AUDIO_DURATION_SECS {
            return Err(ImageHardenError::VorbisError(
                format!("Audio too long: {} seconds", duration_secs)
            ));
        }

        all_samples.extend_from_slice(&packet);
    }

    if all_samples.is_empty() {
        return Err(ImageHardenError::VorbisError("No audio data decoded".to_string()));
    }

    let duration_secs = all_samples.len() as f64 / (sample_rate as f64 * channels as f64);

    Ok(AudioData {
        samples: all_samples,
        sample_rate,
        channels,
        duration_secs,
    })
}

// FLAC decoder (using claxon - pure Rust implementation)
pub fn decode_flac(data: &[u8]) -> Result<AudioData, ImageHardenError> {
    use claxon::FlacReader;

    // Validate input size
    if data.len() > MAX_AUDIO_FILE_SIZE {
        return Err(ImageHardenError::FlacError(
            format!("File too large: {} bytes", data.len())
        ));
    }

    // Validate FLAC signature
    if data.len() < 4 || &data[0..4] != b"fLaC" {
        return Err(ImageHardenError::FlacError("Invalid FLAC signature".to_string()));
    }

    let cursor = std::io::Cursor::new(data);
    let mut reader = FlacReader::new(cursor)
        .map_err(|e| ImageHardenError::FlacError(format!("Failed to initialize reader: {:?}", e)))?;

    let streaminfo = reader.streaminfo();

    // Validate audio parameters
    if streaminfo.sample_rate > MAX_SAMPLE_RATE {
        return Err(ImageHardenError::FlacError(
            format!("Sample rate too high: {} Hz", streaminfo.sample_rate)
        ));
    }
    if streaminfo.channels as u16 > MAX_CHANNELS {
        return Err(ImageHardenError::FlacError(
            format!("Too many channels: {}", streaminfo.channels)
        ));
    }

    let mut all_samples = Vec::new();
    let mut samples = reader.samples();
    let mut sample_count = 0usize;

    while let Some(sample) = samples.next() {
        let sample = sample
            .map_err(|e| ImageHardenError::FlacError(format!("Decode error: {:?}", e)))?;

        // Convert to i16 (FLAC can have various bit depths)
        let sample_i16 = if streaminfo.bits_per_sample <= 16 {
            sample as i16
        } else {
            (sample >> (streaminfo.bits_per_sample - 16)) as i16
        };

        all_samples.push(sample_i16);
        sample_count += 1;

        // Check duration limit
        let duration_secs = sample_count as u64 / (streaminfo.sample_rate as u64 * streaminfo.channels as u64);
        if duration_secs > MAX_AUDIO_DURATION_SECS {
            return Err(ImageHardenError::FlacError(
                format!("Audio too long: {} seconds", duration_secs)
            ));
        }
    }

    if all_samples.is_empty() {
        return Err(ImageHardenError::FlacError("No audio data decoded".to_string()));
    }

    let duration_secs = all_samples.len() as f64 / (streaminfo.sample_rate as f64 * streaminfo.channels as f64);

    Ok(AudioData {
        samples: all_samples,
        sample_rate: streaminfo.sample_rate,
        channels: streaminfo.channels as u16,
        duration_secs,
    })
}

// Generic audio decoder that detects format and dispatches to appropriate decoder
pub fn decode_audio(data: &[u8]) -> Result<AudioData, ImageHardenError> {
    if data.len() < 4 {
        return Err(ImageHardenError::AudioError("File too small".to_string()));
    }

    // Detect format by magic number
    if &data[0..4] == b"fLaC" {
        decode_flac(data)
    } else if &data[0..4] == b"OggS" {
        decode_vorbis(data)
    } else if data.len() >= 2 && data[0] == 0xFF && (data[1] & 0xE0) == 0xE0 {
        decode_mp3(data)
    } else {
        Err(ImageHardenError::AudioError("Unknown audio format".to_string()))
    }
}

// ============================================================================
// VIDEO CONTAINER VALIDATION - DEFENSE AGAINST VM ESCAPE & CPU DESYNC
// ============================================================================
//
// CRITICAL THREAT MODEL:
// Video files are a prime vector for sophisticated attacks including:
// - VM escape exploits via malformed container metadata
// - CPU desynchronization attacks through timing-based codec exploits
// - Hardware acceleration vulnerabilities (GPU buffer overflows)
// - Spectre/Meltdown-style side channel attacks via video decoding
// - Memory corruption in container parsers (MP4, MKV, AVI)
//
// Defense Strategy:
// 1. Validate container format BEFORE sending to any codec
// 2. Enforce strict limits on all video parameters
// 3. Use pure Rust parsers (memory-safe) for container validation
// 4. Sandbox codec execution (FFmpeg in WebAssembly)
// 5. Disable hardware acceleration (prevents GPU exploits)
// 6. Rate-limit and resource-bound all operations

// Security limits for video validation
const MAX_VIDEO_FILE_SIZE: usize = 500 * 1024 * 1024;  // 500 MB
const MAX_VIDEO_DURATION_SECS: u64 = 3600;             // 1 hour
const MAX_VIDEO_WIDTH: u32 = 3840;                     // 4K width
const MAX_VIDEO_HEIGHT: u32 = 2160;                    // 4K height
const MAX_VIDEO_FRAMERATE: u32 = 120;                  // 120 fps
const MAX_VIDEO_BITRATE: u64 = 50_000_000;             // 50 Mbps
const MAX_VIDEO_TRACKS: usize = 8;                     // Max audio/video/subtitle tracks

#[derive(Debug, Clone)]
pub struct VideoMetadata {
    pub container_format: VideoContainerFormat,
    pub width: u32,
    pub height: u32,
    pub duration_secs: f64,
    pub video_tracks: usize,
    pub audio_tracks: usize,
    pub validated: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum VideoContainerFormat {
    MP4,
    MKV,
    WebM,
    AVI,
    Unknown,
}

// Main video validation function - called BEFORE any decoding
pub fn validate_video_container(data: &[u8]) -> Result<VideoMetadata, ImageHardenError> {
    // File size check
    if data.len() > MAX_VIDEO_FILE_SIZE {
        return Err(ImageHardenError::VideoValidationError(
            format!("Video file too large: {} bytes (max: {})", data.len(), MAX_VIDEO_FILE_SIZE)
        ));
    }

    if data.len() < 12 {
        return Err(ImageHardenError::VideoValidationError(
            "Video file too small".to_string()
        ));
    }

    // Detect container format by magic bytes
    let format = detect_video_format(data)?;

    match format {
        VideoContainerFormat::MP4 => validate_mp4_container(data),
        VideoContainerFormat::MKV | VideoContainerFormat::WebM => validate_mkv_container(data),
        VideoContainerFormat::AVI => validate_avi_container(data),
        VideoContainerFormat::Unknown => Err(ImageHardenError::VideoValidationError(
            "Unknown or unsupported video container format".to_string()
        )),
    }
}

// Detect video container format by magic bytes
fn detect_video_format(data: &[u8]) -> Result<VideoContainerFormat, ImageHardenError> {
    if data.len() < 12 {
        return Ok(VideoContainerFormat::Unknown);
    }

    // MP4/MOV: starts with ftyp box
    if data.len() >= 8 && &data[4..8] == b"ftyp" {
        return Ok(VideoContainerFormat::MP4);
    }

    // MKV/WebM: EBML header
    if data.len() >= 4 && &data[0..4] == &[0x1A, 0x45, 0xDF, 0xA3] {
        // Check if it's WebM or MKV by looking at DocType
        if data.len() >= 20 {
            let data_str = String::from_utf8_lossy(&data[0..50]);
            if data_str.contains("webm") {
                return Ok(VideoContainerFormat::WebM);
            }
        }
        return Ok(VideoContainerFormat::MKV);
    }

    // AVI: RIFF...AVI header
    if data.len() >= 12 && &data[0..4] == b"RIFF" && &data[8..12] == b"AVI " {
        return Ok(VideoContainerFormat::AVI);
    }

    Ok(VideoContainerFormat::Unknown)
}

// MP4 container validation using mp4parse (Firefox's Rust parser)
fn validate_mp4_container(data: &[u8]) -> Result<VideoMetadata, ImageHardenError> {
    use mp4parse::{read_mp4, ParseStrictness};
    use std::io::Cursor;

    let mut cursor = Cursor::new(data);

    // Use strict parsing to reject malformed files
    let context = read_mp4(&mut cursor, ParseStrictness::Strict)
        .map_err(|e| ImageHardenError::VideoContainerError(
            format!("MP4 parsing failed: {:?}", e)
        ))?;

    // Validate track counts
    if context.tracks.len() > MAX_VIDEO_TRACKS {
        return Err(ImageHardenError::VideoValidationError(
            format!("Too many tracks: {} (max: {})", context.tracks.len(), MAX_VIDEO_TRACKS)
        ));
    }

    let mut video_tracks = 0;
    let mut audio_tracks = 0;
    let mut max_width = 0u32;
    let mut max_height = 0u32;
    let mut max_duration = 0.0f64;

    for track in &context.tracks {
        match &track.track_type {
            mp4parse::TrackType::Video => {
                video_tracks += 1;

                // Extract video dimensions if available
                if let Some(video_data) = &track.data {
                    // Check for dimensions in various possible locations
                    // This is a simplified check - production code should be more thorough
                    if let Some(tkhd) = &track.tkhd {
                        let width = tkhd.width >> 16;  // Fixed-point to integer
                        let height = tkhd.height >> 16;

                        if width > MAX_VIDEO_WIDTH {
                            return Err(ImageHardenError::VideoValidationError(
                                format!("Video width too large: {} (max: {})", width, MAX_VIDEO_WIDTH)
                            ));
                        }
                        if height > MAX_VIDEO_HEIGHT {
                            return Err(ImageHardenError::VideoValidationError(
                                format!("Video height too large: {} (max: {})", height, MAX_VIDEO_HEIGHT)
                            ));
                        }

                        max_width = max_width.max(width);
                        max_height = max_height.max(height);
                    }
                }

                // Check duration
                if let Some(duration) = track.duration {
                    let duration_secs = duration as f64 / track.timescale.unwrap_or(1) as f64;
                    max_duration = max_duration.max(duration_secs);

                    if duration_secs > MAX_VIDEO_DURATION_SECS as f64 {
                        return Err(ImageHardenError::VideoValidationError(
                            format!("Video too long: {:.1} seconds (max: {})",
                                duration_secs, MAX_VIDEO_DURATION_SECS)
                        ));
                    }
                }
            }
            mp4parse::TrackType::Audio => {
                audio_tracks += 1;
            }
            _ => {}
        }
    }

    if video_tracks == 0 {
        return Err(ImageHardenError::VideoValidationError(
            "No video tracks found in MP4".to_string()
        ));
    }

    Ok(VideoMetadata {
        container_format: VideoContainerFormat::MP4,
        width: max_width,
        height: max_height,
        duration_secs: max_duration,
        video_tracks,
        audio_tracks,
        validated: true,
    })
}

// MKV/WebM container validation
fn validate_mkv_container(data: &[u8]) -> Result<VideoMetadata, ImageHardenError> {
    use matroska::Matroska;
    use std::io::Cursor;

    let cursor = Cursor::new(data);
    let matroska = Matroska::open(cursor)
        .map_err(|e| ImageHardenError::VideoContainerError(
            format!("MKV/WebM parsing failed: {:?}", e)
        ))?;

    let mut video_tracks = 0;
    let mut audio_tracks = 0;
    let mut max_width = 0u32;
    let mut max_height = 0u32;

    // Validate tracks
    for track in &matroska.tracks {
        match track.tracktype {
            1 => {  // Video track
                video_tracks += 1;

                if let Some(video) = &track.video {
                    let width = video.pixel_width as u32;
                    let height = video.pixel_height as u32;

                    if width > MAX_VIDEO_WIDTH {
                        return Err(ImageHardenError::VideoValidationError(
                            format!("MKV video width too large: {} (max: {})", width, MAX_VIDEO_WIDTH)
                        ));
                    }
                    if height > MAX_VIDEO_HEIGHT {
                        return Err(ImageHardenError::VideoValidationError(
                            format!("MKV video height too large: {} (max: {})", height, MAX_VIDEO_HEIGHT)
                        ));
                    }

                    max_width = max_width.max(width);
                    max_height = max_height.max(height);
                }
            }
            2 => {  // Audio track
                audio_tracks += 1;
            }
            _ => {}
        }
    }

    if video_tracks + audio_tracks > MAX_VIDEO_TRACKS {
        return Err(ImageHardenError::VideoValidationError(
            format!("Too many tracks: {} (max: {})",
                video_tracks + audio_tracks, MAX_VIDEO_TRACKS)
        ));
    }

    if video_tracks == 0 {
        return Err(ImageHardenError::VideoValidationError(
            "No video tracks found in MKV/WebM".to_string()
        ));
    }

    // Get duration from info
    let duration_secs = matroska.info.duration.unwrap_or(0.0) / 1_000_000_000.0;  // nanoseconds to seconds

    if duration_secs > MAX_VIDEO_DURATION_SECS as f64 {
        return Err(ImageHardenError::VideoValidationError(
            format!("MKV video too long: {:.1} seconds (max: {})",
                duration_secs, MAX_VIDEO_DURATION_SECS)
        ));
    }

    Ok(VideoMetadata {
        container_format: VideoContainerFormat::MKV,
        width: max_width,
        height: max_height,
        duration_secs,
        video_tracks,
        audio_tracks,
        validated: true,
    })
}

// AVI container validation
fn validate_avi_container(data: &[u8]) -> Result<VideoMetadata, ImageHardenError> {
    // Basic AVI validation using the avi crate
    // AVI is an older format with many parsing vulnerabilities, so we're extra strict

    if data.len() < 12 || &data[0..4] != b"RIFF" || &data[8..12] != b"AVI " {
        return Err(ImageHardenError::VideoValidationError(
            "Invalid AVI signature".to_string()
        ));
    }

    // Parse RIFF chunk size
    let riff_size = u32::from_le_bytes([data[4], data[5], data[6], data[7]]) as usize;

    if riff_size + 8 != data.len() {
        return Err(ImageHardenError::VideoValidationError(
            format!("AVI RIFF size mismatch: declared {} bytes, got {} bytes",
                riff_size + 8, data.len())
        ));
    }

    // Look for 'avih' (AVI header) chunk
    let mut pos = 12;
    let mut found_avih = false;
    let mut width = 0u32;
    let mut height = 0u32;
    let mut duration_microsecs = 0u32;

    while pos + 8 <= data.len() {
        let chunk_id = &data[pos..pos+4];
        let chunk_size = u32::from_le_bytes([
            data[pos+4], data[pos+5], data[pos+6], data[pos+7]
        ]) as usize;

        if pos + 8 + chunk_size > data.len() {
            break;  // Chunk extends past file end
        }

        if chunk_id == b"avih" && chunk_size >= 56 {
            found_avih = true;

            // Parse AVI main header (56 bytes minimum)
            let header_data = &data[pos+8..pos+8+56];
            duration_microsecs = u32::from_le_bytes([
                header_data[0], header_data[1], header_data[2], header_data[3]
            ]);
            width = u32::from_le_bytes([
                header_data[32], header_data[33], header_data[34], header_data[35]
            ]);
            height = u32::from_le_bytes([
                header_data[36], header_data[37], header_data[38], header_data[39]
            ]);

            // Validate dimensions
            if width > MAX_VIDEO_WIDTH {
                return Err(ImageHardenError::VideoValidationError(
                    format!("AVI width too large: {} (max: {})", width, MAX_VIDEO_WIDTH)
                ));
            }
            if height > MAX_VIDEO_HEIGHT {
                return Err(ImageHardenError::VideoValidationError(
                    format!("AVI height too large: {} (max: {})", height, MAX_VIDEO_HEIGHT)
                ));
            }

            break;
        }

        // Move to next chunk (pad to even boundary)
        pos += 8 + chunk_size;
        if chunk_size % 2 == 1 {
            pos += 1;
        }
    }

    if !found_avih {
        return Err(ImageHardenError::VideoValidationError(
            "No AVI header (avih) found".to_string()
        ));
    }

    let duration_secs = duration_microsecs as f64 / 1_000_000.0;

    if duration_secs > MAX_VIDEO_DURATION_SECS as f64 {
        return Err(ImageHardenError::VideoValidationError(
            format!("AVI video too long: {:.1} seconds (max: {})",
                duration_secs, MAX_VIDEO_DURATION_SECS)
        ));
    }

    Ok(VideoMetadata {
        container_format: VideoContainerFormat::AVI,
        width,
        height,
        duration_secs,
        video_tracks: 1,  // AVI typically has single video stream
        audio_tracks: 0,  // Would need more parsing to detect
        validated: true,
    })
}

#![no_main]

use libfuzzer_sys::fuzz_target;
use image_harden::validate_video_container;

fuzz_target!(|data: &[u8]| {
    // Fuzz MP4 container validation
    // Focus: MP4 box parsing, metadata extraction, dimension validation
    let _ = validate_video_container(data);
});

#![no_main]

use libfuzzer_sys::fuzz_target;
use image_harden::validate_video_container;

fuzz_target!(|data: &[u8]| {
    // Fuzz MKV/WebM container validation
    // Focus: EBML parsing, track enumeration, duration calculation
    let _ = validate_video_container(data);
});

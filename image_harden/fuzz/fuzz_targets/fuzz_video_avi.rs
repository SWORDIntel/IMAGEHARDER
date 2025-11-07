#![no_main]

use libfuzzer_sys::fuzz_target;
use image_harden::validate_video_container;

fuzz_target!(|data: &[u8]| {
    // Fuzz AVI container validation
    // Focus: RIFF chunk parsing, header validation, size consistency
    let _ = validate_video_container(data);
});

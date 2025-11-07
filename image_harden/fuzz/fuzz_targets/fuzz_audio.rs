#![no_main]

use libfuzzer_sys::fuzz_target;
use image_harden::decode_audio;

fuzz_target!(|data: &[u8]| {
    // Fuzz the generic audio decoder (auto-detects format)
    // We don't care about the result, just that it doesn't crash or panic
    let _ = decode_audio(data);
});

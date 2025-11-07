#![no_main]

use libfuzzer_sys::fuzz_target;
use image_harden::decode_flac;

fuzz_target!(|data: &[u8]| {
    // Fuzz the FLAC decoder
    // We don't care about the result, just that it doesn't crash or panic
    let _ = decode_flac(data);
});

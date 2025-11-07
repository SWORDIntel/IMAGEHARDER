#![no_main]

use libfuzzer_sys::fuzz_target;
use image_harden::decode_vorbis;

fuzz_target!(|data: &[u8]| {
    // Fuzz the Vorbis decoder
    // We don't care about the result, just that it doesn't crash or panic
    let _ = decode_vorbis(data);
});

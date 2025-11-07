#![no_main]

use libfuzzer_sys::fuzz_target;
use image_harden::decode_mp3;

fuzz_target!(|data: &[u8]| {
    // Fuzz the MP3 decoder
    // We don't care about the result, just that it doesn't crash or panic
    let _ = decode_mp3(data);
});

#![no_main]

use image_harden::decode_webp;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let _ = decode_webp(data);
});

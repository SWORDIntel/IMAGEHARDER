#![no_main]

use image_harden::decode_gif;
use libfuzzer_sys::fuzz_target;

// Fuzz target for GIF decoder
// Tests CVE-2019-15133, CVE-2016-3977 mitigations
fuzz_target!(|data: &[u8]| {
    let _ = decode_gif(data);
});

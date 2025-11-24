#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    #[cfg(feature = "avif")]
    {
        use image_harden::formats::avif;
        let _ = avif::validate_avif(data);
        let _ = avif::decode_avif(data);
    }
});

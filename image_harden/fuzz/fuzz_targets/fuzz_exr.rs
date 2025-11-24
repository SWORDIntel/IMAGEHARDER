#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    #[cfg(feature = "openexr")]
    {
        use image_harden::formats::exr;
        let _ = exr::validate_exr(data);
        let _ = exr::decode_exr(data);
    }
});

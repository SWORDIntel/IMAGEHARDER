#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    #[cfg(feature = "icc")]
    {
        use image_harden::formats::icc;
        let _ = icc::validate_icc_profile(data);
    }
});

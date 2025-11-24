#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    #[cfg(feature = "tiff")]
    {
        use image_harden::formats::tiff;
        let _ = tiff::validate_tiff(data);
        let _ = tiff::decode_tiff(data);
    }
});

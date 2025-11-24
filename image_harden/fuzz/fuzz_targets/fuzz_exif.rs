#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    #[cfg(feature = "exif")]
    {
        use image_harden::formats::exif;
        let _ = exif::validate_exif(data);
    }
});

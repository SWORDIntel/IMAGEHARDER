#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    #[cfg(feature = "jxl")]
    {
        use image_harden::formats::jxl;
        let _ = jxl::validate_jxl(data);
        let _ = jxl::decode_jxl(data);
    }
});

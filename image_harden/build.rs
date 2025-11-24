use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=wrapper.c");
    println!("cargo:rerun-if-changed=build.rs");

    // =============================================================================
    // Compile the C wrapper with CVE mitigations
    // =============================================================================
    // Core formats:
    //   CVE-2015-8540, CVE-2019-7317 (libpng)
    //   CVE-2018-14498 (libjpeg-turbo)
    //   CVE-2019-15133, CVE-2016-3977 (giflib)
    // Extended formats: AVIF, JXL, TIFF, OpenEXR, ICC (lcms2), EXIF
    cc::Build::new()
        .file("wrapper.c")
        .include("/usr/include")
        .include("/usr/local/include")
        .warnings(true)
        .extra_warnings(true)
        .compile("libimage_wrapper.a");

    // =============================================================================
    // Link search paths
    // =============================================================================
    println!("cargo:rustc-link-search=native=/usr/lib/x86_64-linux-gnu");
    println!("cargo:rustc-link-search=native=/usr/local/lib");
    println!("cargo:rustc-link-search=native=/usr/local/lib64");

    // =============================================================================
    // Core image format libraries
    // =============================================================================
    println!("cargo:rustc-link-lib=static=png");
    println!("cargo:rustc-link-lib=static=jpeg");
    println!("cargo:rustc-link-lib=static=gif");
    println!("cargo:rustc-link-lib=static=z");

    // =============================================================================
    // Extended format libraries (conditional - check if available)
    // =============================================================================

    // AVIF support (libavif + dav1d)
    if pkg_config::probe_library("libavif").is_ok() {
        println!("cargo:rustc-link-lib=static=avif");
        println!("cargo:rustc-link-lib=static=dav1d");
        println!("cargo:rustc-cfg=feature=\"avif\"");
    }

    // JPEG XL support
    if pkg_config::probe_library("libjxl").is_ok() {
        println!("cargo:rustc-link-lib=static=jxl");
        println!("cargo:rustc-link-lib=static=jxl_threads");
        println!("cargo:rustc-cfg=feature=\"jxl\"");
    }

    // TIFF support
    if pkg_config::probe_library("libtiff-4").is_ok() {
        println!("cargo:rustc-link-lib=static=tiff");
        println!("cargo:rustc-cfg=feature=\"tiff\"");
    }

    // OpenEXR support
    if pkg_config::probe_library("OpenEXR").is_ok() {
        println!("cargo:rustc-link-lib=static=OpenEXR");
        println!("cargo:rustc-link-lib=static=IlmImf");
        println!("cargo:rustc-link-lib=static=Iex");
        println!("cargo:rustc-cfg=feature=\"openexr\"");
    }

    // ICC color management (lcms2)
    if pkg_config::probe_library("lcms2").is_ok() {
        println!("cargo:rustc-link-lib=static=lcms2");
        println!("cargo:rustc-cfg=feature=\"icc\"");
    }

    // EXIF metadata support
    if pkg_config::probe_library("libexif").is_ok() {
        println!("cargo:rustc-link-lib=static=exif");
        println!("cargo:rustc-cfg=feature=\"exif\"");
    }

    // =============================================================================
    // System libraries
    // =============================================================================
    println!("cargo:rustc-link-lib=dylib=stdc++");
    println!("cargo:rustc-link-lib=dylib=m");

    // =============================================================================
    // Generate FFI bindings
    // =============================================================================
    let mut builder = bindgen::Builder::default()
        .header("/usr/include/png.h")
        .header("/usr/include/jpeglib.h")
        .header("/usr/include/gif_lib.h")
        .header("wrapper.c")
        .clang_arg("-I/usr/include")
        .clang_arg("-I/usr/local/include")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()));

    // Add extended format headers if available
    if PathBuf::from("/usr/local/include/avif/avif.h").exists() {
        builder = builder.header("/usr/local/include/avif/avif.h");
    }

    if PathBuf::from("/usr/local/include/jxl/decode.h").exists() {
        builder = builder.header("/usr/local/include/jxl/decode.h");
    }

    if PathBuf::from("/usr/include/tiffio.h").exists() {
        builder = builder.header("/usr/include/tiffio.h");
    } else if PathBuf::from("/usr/local/include/tiffio.h").exists() {
        builder = builder.header("/usr/local/include/tiffio.h");
    }

    if PathBuf::from("/usr/local/include/OpenEXR/ImfCRgbaFile.h").exists() {
        builder = builder.header("/usr/local/include/OpenEXR/ImfCRgbaFile.h");
    }

    if PathBuf::from("/usr/local/include/lcms2.h").exists() {
        builder = builder.header("/usr/local/include/lcms2.h");
    } else if PathBuf::from("/usr/include/lcms2.h").exists() {
        builder = builder.header("/usr/include/lcms2.h");
    }

    if PathBuf::from("/usr/local/include/libexif/exif-data.h").exists() {
        builder = builder.header("/usr/local/include/libexif/exif-data.h");
    } else if PathBuf::from("/usr/include/libexif/exif-data.h").exists() {
        builder = builder.header("/usr/include/libexif/exif-data.h");
    }

    let bindings = builder
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}

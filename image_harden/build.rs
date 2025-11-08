use std::env;
use std::path::PathBuf;

fn main() {
    // Compile the C wrapper with CVE mitigations
    // CVE-2015-8540, CVE-2019-7317 (libpng)
    // CVE-2018-14498 (libjpeg)
    // CVE-2019-15133, CVE-2016-3977 (giflib)
    cc::Build::new()
        .file("wrapper.c")
        .include("/usr/include")
        .include("/usr/local/include")
        .compile("libimage_wrapper.a");

    // Link to libpng, libjpeg-turbo, giflib, and zlib
    println!("cargo:rustc-link-search=native=/usr/lib/x86_64-linux-gnu");
    println!("cargo:rustc-link-search=native=/usr/local/lib");
    println!("cargo:rustc-link-lib=static=png");
    println!("cargo:rustc-link-lib=static=jpeg");
    println!("cargo:rustc-link-lib=static=gif");
    println!("cargo:rustc-link-lib=static=z");

    // Rerun if wrapper changes
    println!("cargo:rerun-if-changed=wrapper.c");

    // Generate bindings for libpng, libjpeg, and giflib
    let bindings = bindgen::Builder::default()
        .header("/usr/include/png.h")
        .header("/usr/local/include/jpeglib.h")
        .header("/usr/local/include/gif_lib.h")
        .header("wrapper.c")
        .clang_arg("-I/usr/include")
        .clang_arg("-I/usr/local/include")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}

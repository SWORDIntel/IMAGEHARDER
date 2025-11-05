use std::env;
use std::path::PathBuf;

fn main() {
    // Link to libpng, libjpeg-turbo, and zlib
    println!("cargo:rustc-link-search=native=/usr/lib/x86_64-linux-gnu");
    println!("cargo:rustc-link-search=native=/usr/local/lib");
    println!("cargo:rustc-link-lib=static=png");
    println!("cargo:rustc-link-lib=static=jpeg");
    println!("cargo:rustc-link-lib=static=z");

    // Generate bindings
    let bindings = bindgen::Builder::default()
        .header("/usr/include/png.h")
        .header("/usr/local/include/jpeglib.h")
        .clang_arg("-I/usr/local/include")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}

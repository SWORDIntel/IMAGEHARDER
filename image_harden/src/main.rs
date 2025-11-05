use image_harden::{decode_jpeg, decode_png, ImageHardenError};
use std::env;
use std::fs::File;
use std::io::Read;
use std::path::Path;

fn main() -> Result<(), ImageHardenError> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: {} <path_to_image>", args[0]);
        return Ok(());
    }

    let path = Path::new(&args[1]);
    let mut file = File::open(path)?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)?;

    let result = match path.extension().and_then(|s| s.to_str()) {
        Some("png") => decode_png(&buffer),
        Some("jpg") | Some("jpeg") => decode_jpeg(&buffer),
        _ => {
            eprintln!("Unsupported file type");
            return Ok(());
        }
    };

    match result {
        Ok(decoded_image) => {
            println!(
                "Successfully decoded image with size: {}",
                decoded_image.len()
            );
        }
        Err(e) => {
            eprintln!("Failed to decode image: {}", e);
        }
    }

    Ok(())
}

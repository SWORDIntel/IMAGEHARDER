#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

use std::ffi::CStr;
use std::io::Read;
use std::mem;
use thiserror::Error;
use librsvg::SvgHandle;
use ammonia::clean;
use cairo;
use wasmtime::*;
use wasmtime_wasi::{WasiCtx, WasiCtxBuilder};

#[derive(Debug, Error)]
pub enum ImageHardenError {
    #[error("PNG decoding failed: {0}")]
    PngError(String),
    #[error("JPEG decoding failed: {0}")]
    JpegError(String),
    #[error("SVG decoding failed: {0}")]
    SvgError(String),
    #[error("Video decoding failed: {0}")]
    VideoError(String),
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Null pointer encountered")]
    NullPointer,
}

// PNG wrapper
pub fn decode_png(data: &[u8]) -> Result<Vec<u8>, ImageHardenError> {
    unsafe {
        let png_ptr = png_create_read_struct(
            PNG_LIBPNG_VER_STRING.as_ptr() as *const i8,
            std::ptr::null_mut(),
            Some(error_fn),
            Some(warning_fn),
        );
        if png_ptr.is_null() {
            return Err(ImageHardenError::NullPointer);
        }

        let info_ptr = png_create_info_struct(png_ptr);
        if info_ptr.is_null() {
            png_destroy_read_struct(&mut (png_ptr as png_structp), std::ptr::null_mut(), std::ptr::null_mut());
            return Err(ImageHardenError::NullPointer);
        }

        let jmp_buf_ptr = png_jmpbuf_wrapper(png_ptr) as *mut jmp_buf;
        if setjmp(mem::transmute(jmp_buf_ptr)) != 0 {
            png_destroy_read_struct(&mut (png_ptr as png_structp), &mut (info_ptr as png_infop), std::ptr::null_mut());
            return Err(ImageHardenError::PngError("PNG decoding failed".to_string()));
        }

        png_set_user_limits(png_ptr, 8192, 8192);
        png_set_chunk_cache_max(png_ptr, 128);
        png_set_chunk_malloc_max(png_ptr, 256 * 1024);

        let mut cursor = std::io::Cursor::new(data);
        png_set_read_fn(png_ptr, &mut cursor as *mut _ as png_voidp, Some(read_data_fn));

        png_read_info(png_ptr, info_ptr);

        let mut width: png_uint_32 = 0;
        let mut height: png_uint_32 = 0;
        let mut bit_depth: i32 = 0;
        let mut color_type: i32 = 0;

        png_get_IHDR(
            png_ptr,
            info_ptr,
            &mut width,
            &mut height,
            &mut bit_depth,
            &mut color_type,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        );

        png_set_expand(png_ptr);
        png_set_strip_16(png_ptr);
        png_set_gray_to_rgb(png_ptr);
        png_set_add_alpha(png_ptr, 0xff, PNG_FILLER_AFTER as i32);
        png_read_update_info(png_ptr, info_ptr);

        let row_bytes = png_get_rowbytes(png_ptr, info_ptr);
        let mut image_data = vec![0u8; row_bytes * height as usize];
        let mut row_pointers: Vec<png_bytep> = Vec::with_capacity(height as usize);
        for i in 0..height {
            row_pointers.push(image_data.as_mut_ptr().add(i as usize * row_bytes));
        }

        png_read_image(png_ptr, row_pointers.as_mut_ptr());

        png_destroy_read_struct(&mut (png_ptr as png_structp), &mut (info_ptr as png_infop), std::ptr::null_mut());

        Ok(image_data)
    }
}

// JPEG wrapper
struct JpegErrorManager {
    pub base: jpeg_error_mgr,
    pub jmp_buf: jmp_buf,
}

pub fn decode_jpeg(data: &[u8]) -> Result<Vec<u8>, ImageHardenError> {
    unsafe {
        let mut cinfo: jpeg_decompress_struct = std::mem::zeroed();
        let mut err_mgr = JpegErrorManager {
            base: std::mem::zeroed(),
            jmp_buf: std::mem::zeroed(),
        };

        cinfo.err = jpeg_std_error(&mut err_mgr.base);
        err_mgr.base.error_exit = Some(jpeg_error_exit);

        if setjmp(err_mgr.jmp_buf.as_mut_ptr()) != 0 {
            jpeg_destroy_decompress(&mut cinfo);
            return Err(ImageHardenError::JpegError("JPEG decoding failed".to_string()));
        }

        jpeg_CreateDecompress(&mut cinfo, JPEG_LIB_VERSION as i32, std::mem::size_of::<jpeg_decompress_struct>());

        (*cinfo.mem).max_memory_to_use = 64 * 1024 * 1024; // 64 MB
        for m in 0xE0..=0xEF {
            jpeg_save_markers(&mut cinfo, m, 0);
        }
        jpeg_save_markers(&mut cinfo, JPEG_COM as i32, 0);


        jpeg_mem_src(&mut cinfo, data.as_ptr(), data.len() as u64);

        jpeg_read_header(&mut cinfo, 1);

        if cinfo.image_width > 10000 || cinfo.image_height > 10000 {
            return Err(ImageHardenError::JpegError("Image dimensions exceed limits".to_string()));
        }
        cinfo.out_color_space = J_COLOR_SPACE_JCS_RGB;

        jpeg_start_decompress(&mut cinfo);

        let row_stride = cinfo.output_width as usize * cinfo.output_components as usize;
        let mut image_data = vec![0u8; row_stride * cinfo.output_height as usize];

        while cinfo.output_scanline < cinfo.output_height {
            let mut buffer = [image_data.as_mut_ptr().add(cinfo.output_scanline as usize * row_stride)];
            jpeg_read_scanlines(&mut cinfo, buffer.as_mut_ptr(), 1);
        }

        jpeg_finish_decompress(&mut cinfo);
        jpeg_destroy_decompress(&mut cinfo);

        Ok(image_data)
    }
}

// SVG wrapper
pub fn decode_svg(data: &[u8]) -> Result<Vec<u8>, ImageHardenError> {
    let sanitized_svg = clean(std::str::from_utf8(data).map_err(|e| ImageHardenError::SvgError(e.to_string()))?).to_string();
    let handle = SvgHandle::from_str(&sanitized_svg).map_err(|e| ImageHardenError::SvgError(e.to_string()))?;
    let mut surface = cairo::ImageSurface::create(cairo::Format::ARgb32, 256, 256).map_err(|e| ImageHardenError::SvgError(e.to_string()))?;
    let cr = cairo::Context::new(&mut surface).map_err(|e| ImageHardenError::SvgError(e.to_string()))?;
    handle.render_cairo(&cr).map_err(|e| ImageHardenError::SvgError(e.to_string()))?;
    let mut png_data = Vec::new();
    surface.write_to_png(&mut png_data).map_err(|e| ImageHardenError::SvgError(e.to_string()))?;
    Ok(png_data)
}

// Video wrapper
pub fn decode_video(data: &[u8], wasm_path: &str) -> Result<Vec<u8>, ImageHardenError> {
    let engine = Engine::default();
    let mut linker = Linker::new(&engine);
    wasmtime_wasi::add_to_linker(&mut linker, |s| s).unwrap();

    let wasi = WasiCtxBuilder::new()
        .stdin(Box::new(wasmtime_wasi::pipe::ReadPipe::from_slice(data)))
        .stdout(Box::new(wasmtime_wasi::pipe::WritePipe::new_in_memory()))
        .inherit_stderr()
        .build();
    let mut store = Store::new(&engine, wasi);

    let module = Module::from_file(&engine, wasm_path).unwrap();
    linker
        .module(&mut store, "", &module)
        .unwrap();
    linker
        .get_default(&mut store, "")
        .unwrap()
        .typed::<(), ()>(&store)
        .unwrap()
        .call(&mut store, ())
        .unwrap();

    let mut stdout_buf = Vec::new();
    store
        .data_mut()
        .stdout()
        .as_mut()
        .unwrap()
        .try_clone()
        .unwrap()
        .read_to_end(&mut stdout_buf)
        .unwrap();
    Ok(stdout_buf)
}


extern "C" fn error_fn(png_ptr: png_structp, error_msg: png_const_charp) {
    let msg = unsafe { CStr::from_ptr(error_msg).to_string_lossy().into_owned() };
    eprintln!("PNG error: {}", msg);
    unsafe { png_longjmp(png_ptr, 1) };
}

extern "C" fn warning_fn(_png_ptr: png_structp, warning_msg: png_const_charp) {
    let msg = unsafe { CStr::from_ptr(warning_msg).to_string_lossy().into_owned() };
    eprintln!("PNG warning: {}", msg);
}

unsafe extern "C" fn read_data_fn(png_ptr: png_structp, data: png_bytep, length: png_size_t) {
    let io_ptr = png_get_io_ptr(png_ptr);
    let cursor = &mut *(io_ptr as *mut std::io::Cursor<&[u8]>);
    let buffer = std::slice::from_raw_parts_mut(data, length);
    if cursor.read_exact(buffer).is_err() {
        png_error(png_ptr, "Read error".as_ptr() as *const i8);
    }
}

unsafe extern "C" fn jpeg_error_exit(cinfo: j_common_ptr) {
    let err_mgr = (*cinfo).err as *mut JpegErrorManager;
    longjmp((*err_mgr).jmp_buf.as_mut_ptr(), 1);
}

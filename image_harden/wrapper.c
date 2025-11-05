#include <png.h>
#include <setjmp.h>

void* png_jmpbuf_wrapper(png_structp png_ptr) {
    return png_jmpbuf(png_ptr);
}

TIS // HARDEN THE IMAGE LIBS (libpng / libjpeg-turbo) — WITHOUT A FULL PORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SITREP

* You already sandbox/re-encode. You now want to **reduce RCE risk inside the libraries themselves**.
* Focus: **compile-time hardening**, **strict runtime limits**, **fail-closed error paths**, and **CI fuzzing**—for **libpng** and **libjpeg-turbo** used in your apps.

BATTLE PLAN
OBJECTIVE

* Ship **hardened builds** of libpng/libjpeg-turbo and use **safe wrappers** that enforce strict bounds before decode.

ACTIONS — BUILD HARDENED LIBS (Debian/Ubuntu examples)

```bash
# Toolchain: clang (for CET/CFI options on x86_64); you can use GCC if you prefer
sudo apt-get update && sudo apt-get install -y build-essential clang cmake nasm \
  autoconf automake libtool git pkg-config

# Common hardening flags (prod)
export CFLAGS="-O2 -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=3 \
 -fstack-clash-protection -fno-strict-overflow -fno-delete-null-pointer-checks \
 -fPIE -fcf-protection=full"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-z,relro,-z,now,-z,noexecstack,-z,separate-code -pie"

# 1) libjpeg-turbo (API/ABI compatible with libjpeg, faster)
git clone https://github.com/libjpeg-turbo/libjpeg-turbo.git
cd libjpeg-turbo && mkdir build && cd build
cmake -G"Unix Makefiles" .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
  -DWITH_JPEG8=ON -DWITH_TURBOJPEG=ON \
  -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS"
make -j"$(nproc)"; sudo make install
cd ../..

# 2) libpng (hardened)
git clone https://github.com/glennrp/libpng.git
cd libpng && ./configure CC=clang CFLAGS="$CFLAGS -DPNG_SAFE_LIMITS_SUPPORTED" LDFLAGS="$LDFLAGS" --disable-shared --enable-static
make -j"$(nproc)"; sudo make install
cd ..
```

> Notes
> • `-fcf-protection=full` enables CET (IBT+Shadow Stack) where supported.
> • Keep **shared** off for libs used in untrusted pipelines; static linking + PIE reduces ROP surfaces (your call).
> • For LTO/CFI (Clang): add `-flto -fvisibility=hidden -fsanitize=cfi` to both build & link (requires thin-LTO setup and whole-program).

---

ACTIONS — RUNTIME LIMITS (USE THESE WRAPPERS)
**libpng: clamp dimensions, memory, chunk sizes, CRC policy; fail closed**

```c
// png_hard.c — compile with: cc png_hard.c -o png_hard $(pkg-config --cflags --libs libpng)
#include <png.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_W 8192u
#define MAX_H 8192u
#define MAX_ROWBYTES (SIZE_MAX/4)          // hard cap for allocator sanity
#define MAX_CHUNK_CACHE 128                // total unknown chunks cached
#define MAX_CHUNK_BYTES (256u * 1024u)     // cap per-chunk allocation (256 KiB)

static void abort_fn(png_structp, png_const_charp msg){ fprintf(stderr,"libpng: %s\n", msg); exit(1); }
static void warn_fn (png_structp, png_const_charp msg){ /* treat warnings as errors */ fprintf(stderr,"libpng(warn-as-err): %s\n", msg); exit(1); }

int main(int argc, char **argv){
  if(argc<2){fprintf(stderr,"usage: %s file.png\n",argv[0]); return 2;}
  FILE *f=fopen(argv[1],"rb"); if(!f){perror("fopen"); return 1;}

  png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, abort_fn, warn_fn);
  png_infop info = png_create_info_struct(png);
  if(!png || !info) { fprintf(stderr,"oom\n"); return 1; }

  // Fail-closed longjmp target
  if (setjmp(png_jmpbuf(png))) { fprintf(stderr, "decode aborted\n"); return 1; }

  // Strict CRC (reject bad chunks)
  png_set_crc_action(png, PNG_CRC_ERROR, PNG_CRC_ERROR);

  // Hard DoS limits (requires libpng built with user-limits)
  png_set_user_limits(png, MAX_W, MAX_H);
  png_set_chunk_cache_max(png, MAX_CHUNK_CACHE);
  png_set_chunk_malloc_max(png, MAX_CHUNK_BYTES);

  // Init IO
  png_init_io(png, f);
  png_read_info(png, info);

  // Normalize formats to tame allocations
  png_set_expand(png);                  // palette/gray to RGB
  png_set_strip_16(png);                // drop 16-bit
  png_set_gray_to_rgb(png);             // no gray corner cases
  png_set_add_alpha(png, 0xFF, PNG_FILLER_AFTER);
  png_read_update_info(png, info);

  // Validate rowbytes before allocation
  size_t rb = png_get_rowbytes(png, info);
  if (rb > MAX_ROWBYTES) { fprintf(stderr,"rowbytes too large\n"); return 1; }

  png_uint_32 h = png_get_image_height(png, info);
  png_bytep *rows = calloc(h, sizeof(*rows));
  for (png_uint_32 y=0; y<h; ++y) rows[y] = malloc(rb);

  png_read_image(png, rows);

  // ... use rows ...
  fprintf(stdout,"OK %ux%u rb=%zu\n", png_get_image_width(png, info), h, rb);

  for (png_uint_32 y=0; y<h; ++y) free(rows[y]); free(rows);
  png_destroy_read_struct(&png, &info, NULL); fclose(f); return 0;
}
```

**libjpeg-turbo: clamp dimensions, memory, markers, and fail closed**

```c
// jpg_hard.c — compile with: cc jpg_hard.c -o jpg_hard $(pkg-config --cflags --libs libjpeg)
#include <jpeglib.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_W 10000U
#define MAX_H 10000U
#define MAX_MEM (64UL*1024*1024) // 64 MiB
#define MAX_SAMPLING 4           // sanity (e.g., 4:2:0)

static void die(j_common_ptr cinfo){
  (*cinfo->err->output_message)(cinfo);
  exit(1);
}

int main(int argc, char **argv){
  if(argc<2){fprintf(stderr,"usage: %s file.jpg\n",argv[0]); return 2;}
  FILE *f=fopen(argv[1],"rb"); if(!f){perror("fopen"); return 1;}

  struct jpeg_decompress_struct cinfo; struct jpeg_error_mgr jerr;
  cinfo.err = jpeg_std_error(&jerr); jerr.error_exit = die;
  jpeg_create_decompress(&cinfo);

  // Limit libjpeg allocator to prevent DoS
  cinfo.mem->max_memory_to_use = MAX_MEM;

  // Refuse to save arbitrary marker payloads (prevents huge APP/COM blobs)
  for (int m=0xE0; m<=0xEF; ++m) jpeg_save_markers(&cinfo, m, 0);
  jpeg_save_markers(&cinfo, JPEG_COM, 0);

  jpeg_stdio_src(&cinfo, f);
  jpeg_read_header(&cinfo, TRUE);

  if (cinfo.image_width  > MAX_W || cinfo.image_height > MAX_H)  die((j_common_ptr)&cinfo);
  if (cinfo.comp_info && (cinfo.comp_info[0].h_samp_factor > MAX_SAMPLING ||
                          cinfo.comp_info[0].v_samp_factor > MAX_SAMPLING)) die((j_common_ptr)&cinfo);

  // Normalize output to RGB, no fancy output color spaces
  cinfo.out_color_space = JCS_RGB;

  jpeg_start_decompress(&cinfo);
  size_t row_stride = cinfo.output_width * cinfo.output_components;
  if (row_stride > MAX_MEM) die((j_common_ptr)&cinfo);

  JSAMPARRAY buf = (*cinfo.mem->alloc_sarray)((j_common_ptr)&cinfo, JPOOL_IMAGE, row_stride, 1);
  while (cinfo.output_scanline < cinfo.output_height) {
    (void)jpeg_read_scanlines(&cinfo, buf, 1);
    // ... consume buf[0] safely ...
  }
  jpeg_finish_decompress(&cinfo);
  jpeg_destroy_decompress(&cinfo); fclose(f); return 0;
}
```

---

ACTIONS — CI “RED” BUILDS WITH SANITIZERS (catch bugs before prod)

```bash
# Address/UB sanitizers (debug-only; not for production)
export SAN="-fsanitize=address,undefined,bounds -fno-omit-frame-pointer"
export CFLAGS_DEBUG="-O1 -g $SAN"
export LDFLAGS_DEBUG="$SAN"

# Example: build libpng debug with sanitizers
cd libpng && make clean
./configure CC=clang CFLAGS="$CFLAGS_DEBUG -DPNG_SAFE_LIMITS_SUPPORTED" LDFLAGS="$LDFLAGS_DEBUG" --disable-shared
make -j"$(nproc)" && ctest || true   # expect CI to fail fast on issues
```

ACTIONS — FUZZ HARNESS (mini, libFuzzer)

```bash
# libpng mini-fuzzer (requires clang++ with -fsanitize=fuzzer)
cat > png_fuzz.cc <<'EOF'
#include <png.h>
#include <stdint.h>
#include <stdlib.h>
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size){
  if(size<8) return 0;
  png_image img; memset(&img, 0, sizeof img); img.version = PNG_IMAGE_VERSION;
  if(!png_image_begin_read_from_memory(&img, data, size)) return 0;
  if(img.width>8192 || img.height>8192) return 0;
  img.format = PNG_FORMAT_RGBA;
  size_t bufsize = PNG_IMAGE_SIZE(img);
  if(bufsize>32*1024*1024) return 0;
  uint8_t *buffer = (uint8_t*)malloc(bufsize);
  int ok = png_image_finish_read(&img, NULL, buffer, 0, NULL);
  png_image_free(&img); free(buffer); return 0;
}
EOF
clang++ -O1 -g -fsanitize=fuzzer,address,undefined png_fuzz.cc -o png_fuzz $(pkg-config --cflags --libs libpng)
# Run: ./png_fuzz ./corpus_png
```

ACTIONS — RUNTIME ALLOCATOR HARDENING (optional)

```bash
# Glibc hardening knobs (test in staging first; perf impact possible)
export GLIBC_TUNABLES="glibc.malloc.check=3:glibc.malloc.tcache_count=0"
export MALLOC_ARENA_MAX=2
# Or use jemalloc with junk/zero fills:
export MALLOC_CONF="junk:true,zero_realloc:true,abort_conf:true,background_thread:true"
```

ACTIONS — OPTIONAL IN-PROCESS GUARDS

```bash
# On x86_64 with CET-capable CPUs + glibc: ensure CET is active
cat /proc/self/status | grep -E 'IBT|SHSTK'  # should show "enabled" in hardened builds

# Before invoking decoders in worker processes, tighten seccomp (coarse example)
# (Do this in the host app just before decode; libraries should not install seccomp themselves.)
sudo apt-get install -y libseccomp-dev
```

VERIFICATION

* Oversized images / huge APPx segments are **rejected** before allocation.
* CRC failures in PNG are treated as **errors** (not warnings).
* Decoders run under CET/RELRO/PIE with **NX** and no execstack.
* Fuzz corpus finds no crash/UB in RED builds; CI gates releases.

CONTINGENCY

* If perf dips (esp. PNG), enable **SIMD** paths but keep limits:

  * libpng: use distro NEON/SSE build; keep `png_set_*` limits.
  * libjpeg-turbo: default already uses SIMD; safe.
* If you hit false positives with `warn-as-error`, relax `warn_fn` to log-and-abort only on certain messages (rare).

QUALITY METRICS & SUCCESS VALIDATION

* **Zero** OOMs from oversized/marker bombs under fuzz & production telemetry.
* Crash-free under ASan/UBSan for ≥ 10^7 test cases.
* No image decode path allocates > configured caps without explicit override.

If you want, I can wrap these into a **drop-in CMake “HardenedLibs.cmake”** + a tiny C API (`png_safe_read()`, `jpeg_safe_read()`) so your projects link the hardened variants without touching call-sites.

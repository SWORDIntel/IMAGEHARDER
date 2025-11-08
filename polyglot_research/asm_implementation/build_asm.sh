#!/bin/bash
# Build script for x86-64 Assembly Polyglot Generator

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Assembly Polyglot Generator Build Script              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check for NASM
if ! command -v nasm &> /dev/null; then
    echo "[!] NASM assembler not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y nasm
fi

echo "[*] Assembling polyglot_generator.asm..."
nasm -f elf64 polyglot_generator.asm -o polyglot_gen_asm.o

echo "[*] Linking..."
ld -o polyglot_gen_asm polyglot_gen_asm.o

echo "[*] Stripping symbols (optional)..."
strip --strip-all polyglot_gen_asm

echo ""
echo "[✓] Build complete!"
echo ""
echo "Binary size:"
ls -lh polyglot_gen_asm
echo ""
echo "Usage:"
echo "  ./polyglot_gen_asm gif example_payload.sh test.gif"
echo "  ./polyglot_gen_asm png example_payload.sh test.png"
echo "  ./polyglot_gen_asm jpeg example_payload.sh test.jpg"
echo ""

#!/bin/bash
set -e

# Test Corpus Generator for Fuzzing
# Creates valid and malformed media files for testing

CORPUS_DIR="./test-corpus"
mkdir -p "$CORPUS_DIR"/{png,jpeg,mp3,ogg,flac,mp4,mkv,avi}/valid
mkdir -p "$CORPUS_DIR"/{png,jpeg,mp3,ogg,flac,mp4,mkv,avi}/malformed

echo "Generating test corpus for fuzzing..."

# PNG valid samples
if command -v convert &> /dev/null; then
    echo "[PNG] Generating valid samples..."
    for size in 10x10 100x100 500x500 1920x1080 3840x2160; do
        convert -size $size xc:blue "$CORPUS_DIR/png/valid/blue_$size.png"
    done

    # PNG malformed samples
    echo "[PNG] Generating malformed samples..."
    # Truncated
    head -c 100 "$CORPUS_DIR/png/valid/blue_100x100.png" > "$CORPUS_DIR/png/malformed/truncated.png"
    # Wrong header
    echo "PNG_FAKE_HEADER" > "$CORPUS_DIR/png/malformed/bad_header.png"
    # Oversized dimensions (in header)
    cp "$CORPUS_DIR/png/valid/blue_100x100.png" "$CORPUS_DIR/png/malformed/huge_dims.png"
    printf '\xFF\xFF\xFF\xFF' | dd of="$CORPUS_DIR/png/malformed/huge_dims.png" bs=1 seek=16 count=4 conv=notrunc 2>/dev/null
fi

# JPEG valid samples
if command -v convert &> /dev/null; then
    echo "[JPEG] Generating valid samples..."
    for quality in 10 50 90 100; do
        convert -size 1920x1080 xc:red -quality $quality "$CORPUS_DIR/jpeg/valid/red_q$quality.jpg"
    done

    echo "[JPEG] Generating malformed samples..."
    # Bad JPEG marker
    echo -ne '\xFF\xD8\xFF\xE0\x00\x10JFIF' > "$CORPUS_DIR/jpeg/malformed/bad_marker.jpg"
    # Truncated
    head -c 500 "$CORPUS_DIR/jpeg/valid/red_q90.jpg" > "$CORPUS_DIR/jpeg/malformed/truncated.jpg"
fi

# MP3 valid samples
if command -v ffmpeg &> /dev/null; then
    echo "[MP3] Generating valid samples..."
    for duration in 1 10 30; do
        ffmpeg -f lavfi -i sine=frequency=440:duration=$duration \
               -b:a 192k "$CORPUS_DIR/mp3/valid/${duration}sec.mp3" -y 2>/dev/null
    done

    echo "[MP3] Generating malformed samples..."
    # Bad MP3 header
    echo -ne '\xFF\xFB\x90\x00' > "$CORPUS_DIR/mp3/malformed/bad_header.mp3"
    # Truncated
    head -c 1000 "$CORPUS_DIR/mp3/valid/10sec.mp3" > "$CORPUS_DIR/mp3/malformed/truncated.mp3"
fi

# Ogg Vorbis valid samples
if command -v ffmpeg &> /dev/null; then
    echo "[OGG] Generating valid samples..."
    ffmpeg -f lavfi -i sine=frequency=1000:duration=10 \
           -c:a libvorbis "$CORPUS_DIR/ogg/valid/10sec.ogg" -y 2>/dev/null

    echo "[OGG] Generating malformed samples..."
    # Bad Ogg signature
    echo "OGG_FAKE" > "$CORPUS_DIR/ogg/malformed/bad_signature.ogg"
    # Truncated
    head -c 500 "$CORPUS_DIR/ogg/valid/10sec.ogg" > "$CORPUS_DIR/ogg/malformed/truncated.ogg"
fi

# FLAC valid samples
if command -v ffmpeg &> /dev/null; then
    echo "[FLAC] Generating valid samples..."
    ffmpeg -f lavfi -i sine=frequency=1000:duration=10 \
           -c:a flac "$CORPUS_DIR/flac/valid/10sec.flac" -y 2>/dev/null

    echo "[FLAC] Generating malformed samples..."
    # Bad FLAC signature
    echo "fLaC_FAKE" > "$CORPUS_DIR/flac/malformed/bad_signature.flac"
    # Truncated
    head -c 1000 "$CORPUS_DIR/flac/valid/10sec.flac" > "$CORPUS_DIR/flac/malformed/truncated.flac"
fi

# MP4 valid samples
if command -v ffmpeg &> /dev/null; then
    echo "[MP4] Generating valid samples..."
    for resolution in 640x480 1920x1080; do
        ffmpeg -f lavfi -i testsrc=duration=5:size=$resolution:rate=30 \
               -c:v libx264 -preset fast "$CORPUS_DIR/mp4/valid/${resolution}_5sec.mp4" -y 2>/dev/null
    done

    echo "[MP4] Generating malformed samples..."
    # Bad ftyp box
    echo -ne '\x00\x00\x00\x18ftypBRAND' > "$CORPUS_DIR/mp4/malformed/bad_ftyp.mp4"
    # Truncated
    head -c 5000 "$CORPUS_DIR/mp4/valid/640x480_5sec.mp4" > "$CORPUS_DIR/mp4/malformed/truncated.mp4"
    # Huge dimension in tkhd
    cp "$CORPUS_DIR/mp4/valid/640x480_5sec.mp4" "$CORPUS_DIR/mp4/malformed/huge_dims.mp4"
fi

# MKV valid samples
if command -v ffmpeg &> /dev/null; then
    echo "[MKV] Generating valid samples..."
    ffmpeg -f lavfi -i testsrc=duration=5:size=1280x720:rate=30 \
           -c:v libx264 "$CORPUS_DIR/mkv/valid/720p_5sec.mkv" -y 2>/dev/null

    echo "[MKV] Generating malformed samples..."
    # Bad EBML header
    echo -ne '\x1A\x45\xDF\xA3\x00\x00\x00\x00' > "$CORPUS_DIR/mkv/malformed/bad_ebml.mkv"
    # Truncated
    head -c 3000 "$CORPUS_DIR/mkv/valid/720p_5sec.mkv" > "$CORPUS_DIR/mkv/malformed/truncated.mkv"
fi

# AVI valid samples
if command -v ffmpeg &> /dev/null; then
    echo "[AVI] Generating valid samples..."
    ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 \
           -c:v mpeg4 "$CORPUS_DIR/avi/valid/480p_5sec.avi" -y 2>/dev/null

    echo "[AVI] Generating malformed samples..."
    # Bad RIFF header
    echo -ne 'RIFF\x00\x00\x00\x00AVI ' > "$CORPUS_DIR/avi/malformed/bad_riff.avi"
    # Truncated
    head -c 2000 "$CORPUS_DIR/avi/valid/480p_5sec.avi" > "$CORPUS_DIR/avi/malformed/truncated.avi"
fi

# Generate edge case samples
echo "Generating edge cases..."

# Zero-byte files
for format in png jpeg mp3 ogg flac mp4 mkv avi; do
    touch "$CORPUS_DIR/$format/malformed/zero_byte.$format"
done

# Single-byte files
for format in png jpeg mp3 ogg flac mp4 mkv avi; do
    echo -n 'X' > "$CORPUS_DIR/$format/malformed/single_byte.$format"
done

# Random data files
for format in png jpeg mp3 ogg flac mp4 mkv avi; do
    head -c 10000 /dev/urandom > "$CORPUS_DIR/$format/malformed/random_data.$format"
done

echo "==========================================="
echo "Test corpus generation complete!"
echo "==========================================="
echo "Location: $CORPUS_DIR"
echo ""
echo "Summary:"
find "$CORPUS_DIR" -type f | wc -l | xargs echo "Total files:"
find "$CORPUS_DIR" -path '*/valid/*' -type f | wc -l | xargs echo "Valid samples:"
find "$CORPUS_DIR" -path '*/malformed/*' -type f | wc -l | xargs echo "Malformed samples:"
echo ""
echo "Use with:"
echo "  cargo fuzz run fuzz_png corpus/png/valid corpus/png/malformed"
echo "  ./benchmark.sh"
echo "==========================================="

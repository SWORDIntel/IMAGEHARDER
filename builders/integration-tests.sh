#!/bin/bash
set -e

# Integration Test Suite for Media Hardening
# Tests end-to-end processing of images, audio, and video files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BINARY="./image_harden/target/release/image_harden_cli"
TEST_DIR="./integration-test-tmp"
CORPUS_DIR="./test-corpus"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

echo "============================================"
echo "Media Hardening Integration Test Suite"
echo "============================================"
echo ""

# Check if binary exists
if [ ! -f "$BINARY" ]; then
    echo -e "${RED}[ERROR]${NC} Binary not found: $BINARY"
    echo "[INFO] Building..."
    cd image_harden && cargo build --release && cd ..
fi

# Create test directory
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Helper function to run a test
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_result="$3"  # "pass" or "fail"

    echo -n "[TEST] $test_name ... "

    if eval "$command" > "$TEST_DIR/test_output.log" 2>&1; then
        actual_result="pass"
    else
        actual_result="fail"
    fi

    if [ "$actual_result" == "$expected_result" ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected: $expected_result, Got: $actual_result"
        echo "  Output: $(cat $TEST_DIR/test_output.log | head -n 3)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

echo "=== Basic Functionality Tests ==="
echo ""

# Test 1: Version flag
run_test "CLI --version flag" "$BINARY --version" "pass"

# Test 2: Health check
run_test "CLI --health-check flag" "$BINARY --health-check" "pass"

# Test 3: Help flag
run_test "CLI --help flag" "$BINARY --help" "pass"

echo ""
echo "=== Image Processing Tests ==="
echo ""

# Create test images
if command -v convert &> /dev/null; then
    # Valid PNG
    convert -size 100x100 xc:red "$TEST_DIR/valid_100x100.png" 2>/dev/null
    run_test "Process valid PNG (100x100)" "$BINARY $TEST_DIR/valid_100x100.png" "pass"

    # Valid JPEG
    convert -size 640x480 xc:blue -quality 90 "$TEST_DIR/valid_640x480.jpg" 2>/dev/null
    run_test "Process valid JPEG (640x480)" "$BINARY $TEST_DIR/valid_640x480.jpg" "pass"

    # Large PNG (4K)
    convert -size 3840x2160 xc:green "$TEST_DIR/large_4k.png" 2>/dev/null
    run_test "Process large PNG (4K)" "$BINARY $TEST_DIR/large_4k.png" "pass"

    # Malformed PNG (truncated)
    head -c 100 "$TEST_DIR/valid_100x100.png" > "$TEST_DIR/truncated.png"
    run_test "Reject truncated PNG" "$BINARY $TEST_DIR/truncated.png" "fail"

    # Bad PNG header
    echo "NOT_A_PNG_FILE" > "$TEST_DIR/bad_header.png"
    run_test "Reject bad PNG header" "$BINARY $TEST_DIR/bad_header.png" "fail"
else
    echo -e "${YELLOW}[SKIP]${NC} ImageMagick not available, skipping image tests"
fi

echo ""
echo "=== Audio Processing Tests ==="
echo ""

if command -v ffmpeg &> /dev/null; then
    # Valid MP3
    ffmpeg -f lavfi -i sine=frequency=440:duration=1 -b:a 192k "$TEST_DIR/valid_1sec.mp3" -y 2>/dev/null
    run_test "Process valid MP3 (1 second)" "$BINARY $TEST_DIR/valid_1sec.mp3" "pass"

    # Valid Ogg Vorbis
    ffmpeg -f lavfi -i sine=frequency=1000:duration=2 -c:a libvorbis "$TEST_DIR/valid_2sec.ogg" -y 2>/dev/null
    run_test "Process valid Ogg Vorbis (2 seconds)" "$BINARY $TEST_DIR/valid_2sec.ogg" "pass"

    # Valid FLAC
    ffmpeg -f lavfi -i sine=frequency=880:duration=1 -c:a flac "$TEST_DIR/valid_1sec.flac" -y 2>/dev/null
    run_test "Process valid FLAC (1 second)" "$BINARY $TEST_DIR/valid_1sec.flac" "pass"

    # Truncated MP3
    head -c 500 "$TEST_DIR/valid_1sec.mp3" > "$TEST_DIR/truncated.mp3"
    run_test "Reject truncated MP3" "$BINARY $TEST_DIR/truncated.mp3" "fail"

    # Bad MP3 header
    echo -ne '\\xFF\\xFB\\x00\\x00' > "$TEST_DIR/bad_header.mp3"
    run_test "Reject bad MP3 header" "$BINARY $TEST_DIR/bad_header.mp3" "fail"
else
    echo -e "${YELLOW}[SKIP]${NC} FFmpeg not available, skipping audio tests"
fi

echo ""
echo "=== Video Processing Tests ==="
echo ""

if command -v ffmpeg &> /dev/null; then
    # Valid MP4
    ffmpeg -f lavfi -i testsrc=duration=2:size=640x480:rate=30 \
           -c:v libx264 -preset ultrafast "$TEST_DIR/valid_640x480_2sec.mp4" -y 2>/dev/null
    run_test "Process valid MP4 (640x480, 2 sec)" "$BINARY $TEST_DIR/valid_640x480_2sec.mp4" "pass"

    # Valid MKV
    ffmpeg -f lavfi -i testsrc=duration=1:size=320x240:rate=30 \
           -c:v libx264 -preset ultrafast "$TEST_DIR/valid_320x240_1sec.mkv" -y 2>/dev/null
    run_test "Process valid MKV (320x240, 1 sec)" "$BINARY $TEST_DIR/valid_320x240_1sec.mkv" "pass"

    # Truncated MP4
    head -c 1000 "$TEST_DIR/valid_640x480_2sec.mp4" > "$TEST_DIR/truncated.mp4"
    run_test "Reject truncated MP4" "$BINARY $TEST_DIR/truncated.mp4" "fail"

    # Bad MP4 header
    echo -ne '\\x00\\x00\\x00\\x18ftypBAD!' > "$TEST_DIR/bad_header.mp4"
    run_test "Reject bad MP4 header" "$BINARY $TEST_DIR/bad_header.mp4" "fail"
else
    echo -e "${YELLOW}[SKIP]${NC} FFmpeg not available, skipping video tests"
fi

echo ""
echo "=== Edge Case Tests ==="
echo ""

# Zero-byte file
touch "$TEST_DIR/zero_byte.png"
run_test "Reject zero-byte file" "$BINARY $TEST_DIR/zero_byte.png" "fail"

# Single-byte file
echo -n 'X' > "$TEST_DIR/single_byte.mp3"
run_test "Reject single-byte file" "$BINARY $TEST_DIR/single_byte.mp3" "fail"

# Random data
head -c 10000 /dev/urandom > "$TEST_DIR/random_data.jpg"
run_test "Reject random data as JPEG" "$BINARY $TEST_DIR/random_data.jpg" "fail"

# Non-existent file
run_test "Reject non-existent file" "$BINARY /nonexistent/file.png" "fail"

echo ""
echo "=== Security Tests ==="
echo ""

# Test file size limits (if we have corpus files larger than limits)
if [ -d "$CORPUS_DIR" ]; then
    # Test with corpus files
    for format in png jpeg mp3 ogg flac mp4; do
        if [ -d "$CORPUS_DIR/$format/malformed" ]; then
            malformed_count=$(find "$CORPUS_DIR/$format/malformed" -type f | wc -l)
            if [ "$malformed_count" -gt 0 ]; then
                # Pick first malformed file
                malformed_file=$(find "$CORPUS_DIR/$format/malformed" -type f | head -n 1)
                run_test "Reject malformed $format from corpus" "$BINARY $malformed_file" "fail"
            fi
        fi
    done
fi

# Test metadata injection (simulate .ps1 in MP3 - the original threat)
if command -v ffmpeg &> /dev/null; then
    # Create MP3 with suspicious metadata
    ffmpeg -f lavfi -i sine=frequency=440:duration=1 \
           -metadata comment="powershell.exe -encodedCommand ..." \
           -b:a 192k "$TEST_DIR/suspicious_metadata.mp3" -y 2>/dev/null

    # Note: This should still process (metadata is separate from embedded files)
    # A more sophisticated check would scan for embedded data streams
    run_test "Process MP3 with suspicious metadata" "$BINARY $TEST_DIR/suspicious_metadata.mp3" "pass"
fi

echo ""
echo "=== Resource Limit Tests ==="
echo ""

# Test concurrent processing (basic stress test)
if command -v convert &> /dev/null; then
    echo -n "[TEST] Concurrent processing (10 files) ... "

    # Create 10 small test images
    for i in {1..10}; do
        convert -size 50x50 xc:red "$TEST_DIR/concurrent_$i.png" 2>/dev/null
    done

    # Process them concurrently
    pids=()
    for i in {1..10}; do
        "$BINARY" "$TEST_DIR/concurrent_$i.png" > /dev/null 2>&1 &
        pids+=($!)
    done

    # Wait for all
    all_success=true
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            all_success=false
        fi
    done

    if [ "$all_success" = true ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
fi

echo ""
echo "=== Corpus-based Fuzzing Verification ==="
echo ""

# If test corpus exists, run quick verification
if [ -d "$CORPUS_DIR" ]; then
    echo "[INFO] Found test corpus at $CORPUS_DIR"

    # Count valid and malformed files
    valid_count=$(find "$CORPUS_DIR" -path '*/valid/*' -type f 2>/dev/null | wc -l)
    malformed_count=$(find "$CORPUS_DIR" -path '*/malformed/*' -type f 2>/dev/null | wc -l)

    echo "[INFO] Valid corpus files: $valid_count"
    echo "[INFO] Malformed corpus files: $malformed_count"

    # Quick smoke test on a few corpus files
    if [ "$valid_count" -gt 0 ]; then
        echo -n "[TEST] Process random valid corpus file ... "
        random_valid=$(find "$CORPUS_DIR" -path '*/valid/*' -type f | shuf -n 1)
        if "$BINARY" "$random_valid" > /dev/null 2>&1; then
            echo -e "${GREEN}PASS${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}FAIL${NC}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    fi

    if [ "$malformed_count" -gt 0 ]; then
        echo -n "[TEST] Reject random malformed corpus file ... "
        random_malformed=$(find "$CORPUS_DIR" -path '*/malformed/*' -type f | shuf -n 1)
        if "$BINARY" "$random_malformed" > /dev/null 2>&1; then
            echo -e "${RED}FAIL${NC} (should have rejected)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        else
            echo -e "${GREEN}PASS${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        fi
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} No test corpus found. Run ./test_corpus_generator.sh first."
fi

echo ""
echo "============================================"
echo "Test Results"
echo "============================================"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo ""

# Cleanup
echo "[INFO] Cleaning up test directory: $TEST_DIR"
rm -rf "$TEST_DIR"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi

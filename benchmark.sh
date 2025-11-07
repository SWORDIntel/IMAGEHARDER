#!/bin/bash
set -e

# Performance Benchmarking Suite for Media Hardening
# Measures throughput, latency, memory usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BENCHMARK_DIR="./benchmarks"
RESULTS_DIR="./benchmark-results"
CORPUS_DIR="./test-corpus"
BINARY="./image_harden/target/release/image_harden_cli"

mkdir -p "$RESULTS_DIR"

echo "============================================"
echo "Media Hardening Performance Benchmarks"
echo "============================================"
echo "Date: $(date)"
echo "Binary: $BINARY"
echo "System: $(uname -a)"
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "RAM: $(free -h | grep Mem | awk '{print $2}')"
echo "============================================"
echo ""

# Check if binary exists
if [ ! -f "$BINARY" ]; then
    echo "[ERROR] Binary not found: $BINARY"
    echo "[INFO] Building..."
    cd image_harden && cargo build --release && cd ..
fi

# Create test corpus if it doesn't exist
if [ ! -d "$CORPUS_DIR" ]; then
    echo "[INFO] Creating test corpus..."
    mkdir -p "$CORPUS_DIR"/{png,jpeg,mp3,ogg,flac,mp4,mkv,avi}

    # Generate test files (requires imagemagick, ffmpeg)
    if command -v convert &> /dev/null; then
        # PNG test files (various sizes)
        convert -size 100x100 xc:red "$CORPUS_DIR/png/100x100.png"
        convert -size 1920x1080 xc:blue "$CORPUS_DIR/png/1080p.png"
        convert -size 3840x2160 xc:green "$CORPUS_DIR/png/4k.png"
    fi

    if command -v ffmpeg &> /dev/null; then
        # MP3 test files
        ffmpeg -f lavfi -i sine=frequency=1000:duration=10 "$CORPUS_DIR/mp3/10sec.mp3" -y 2>/dev/null

        # Video test files
        ffmpeg -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 \
               -c:v libx264 "$CORPUS_DIR/mp4/1080p_10sec.mp4" -y 2>/dev/null
    fi

    echo "[INFO] Test corpus created"
fi

# Function to benchmark a single file
benchmark_file() {
    local file="$1"
    local iterations="${2:-10}"

    echo "Benchmarking: $(basename $file)"

    local total_time=0
    local peak_memory=0

    for i in $(seq 1 $iterations); do
        # Measure time and memory
        /usr/bin/time -f "%e %M" -o /tmp/bench_result "$BINARY" "$file" > /dev/null 2>&1 || true

        if [ -f /tmp/bench_result ]; then
            local time_sec=$(cat /tmp/bench_result | awk '{print $1}')
            local mem_kb=$(cat /tmp/bench_result | awk '{print $2}')

            total_time=$(echo "$total_time + $time_sec" | bc)
            if [ "$mem_kb" -gt "$peak_memory" ]; then
                peak_memory=$mem_kb
            fi
        fi
    done

    local avg_time=$(echo "scale=4; $total_time / $iterations" | bc)
    local throughput=$(echo "scale=2; $iterations / $total_time" | bc)

    echo "  Average time: ${avg_time}s"
    echo "  Throughput: ${throughput} files/sec"
    echo "  Peak memory: $((peak_memory / 1024))MB"
    echo ""

    # Save results
    echo "$(basename $file),$avg_time,$throughput,$peak_memory" >> "$RESULTS_DIR/results.csv"
}

# Initialize results CSV
echo "File,Avg Time (s),Throughput (files/s),Peak Memory (KB)" > "$RESULTS_DIR/results.csv"

# Benchmark Images
echo "=== Benchmarking Images ==="
for file in "$CORPUS_DIR"/png/*.png; do
    [ -f "$file" ] && benchmark_file "$file" 10
done

for file in "$CORPUS_DIR"/jpeg/*.{jpg,jpeg} 2>/dev/null; do
    [ -f "$file" ] && benchmark_file "$file" 10
done

# Benchmark Audio
echo "=== Benchmarking Audio ==="
for file in "$CORPUS_DIR"/mp3/*.mp3; do
    [ -f "$file" ] && benchmark_file "$file" 10
done

for file in "$CORPUS_DIR"/ogg/*.ogg; do
    [ -f "$file" ] && benchmark_file "$file" 10
done

for file in "$CORPUS_DIR"/flac/*.flac; do
    [ -f "$file" ] && benchmark_file "$file" 10
done

# Benchmark Video
echo "=== Benchmarking Video ==="
for file in "$CORPUS_DIR"/mp4/*.mp4; do
    [ -f "$file" ] && benchmark_file "$file" 5  # Fewer iterations for video
done

for file in "$CORPUS_DIR"/mkv/*.mkv; do
    [ -f "$file" ] && benchmark_file "$file" 5
done

# Generate report
echo "============================================"
echo "Benchmark Summary"
echo "============================================"
echo ""
column -t -s, "$RESULTS_DIR/results.csv"
echo ""
echo "Full results saved to: $RESULTS_DIR/results.csv"
echo "============================================"

# Generate gnuplot graph (if available)
if command -v gnuplot &> /dev/null; then
    cat > /tmp/benchmark.gnuplot <<'EOF'
set terminal png size 1200,800
set output './benchmark-results/benchmark.png'
set datafile separator ","
set title "Media Hardening Performance Benchmarks"
set xlabel "File"
set ylabel "Processing Time (seconds)"
set xtics rotate by -45
set grid
set key outside right top
plot './benchmark-results/results.csv' using 2:xtic(1) with linespoints title "Avg Time", \
     '' using 3 with linespoints title "Throughput"
EOF
    gnuplot /tmp/benchmark.gnuplot
    echo "Graph saved to: $RESULTS_DIR/benchmark.png"
fi

exit 0

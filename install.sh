#!/bin/bash
#
# IMAGEHARDER Unified Installer
# Single entrypoint for installing all IMAGEHARDER components
#
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
IMAGEHARDEN_CPU="${IMAGEHARDEN_CPU:-generic}"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/install-$(date +%Y%m%d-%H%M%S).log}"
CHECKPOINT_DIR="${CHECKPOINT_DIR:-$SCRIPT_DIR/.install-checkpoints}"

# Component flags
INSTALL_CORE=0
INSTALL_EXTENDED=0
INSTALL_AUDIO=0
INSTALL_FFMPEG_WASM=0
INSTALL_DRIVERS=0
INSTALL_AUDIO_DRIVERS=0
INSTALL_RUST=0
INSTALL_TESTS=0
INSTALL_BENCHMARK=0
INSTALL_SBOM=0
INSTALL_ALL=0

# Non-interactive mode flag
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"

# Error tracking
ERRORS=()
WARNINGS=()

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
    WARNINGS+=("$1")
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    ERRORS+=("$1")
}

log_section() {
    echo -e "\n${BLUE}============================================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}$1${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}============================================================${NC}\n" | tee -a "$LOG_FILE"
}

# Checkpoint system for rollback
create_checkpoint() {
    local checkpoint_name="$1"
    mkdir -p "$CHECKPOINT_DIR"
    touch "$CHECKPOINT_DIR/$checkpoint_name"
    log_info "Checkpoint created: $checkpoint_name"
}

checkpoint_exists() {
    [ -f "$CHECKPOINT_DIR/$1" ]
}

# Check and ensure sudo access
check_sudo() {
    # If already root, use empty sudo command
    if [[ $EUID -eq 0 ]]; then
        SUDO_CMD=""
        log_info "Running as root - using direct commands"
        return 0
    fi
    
    # Check if sudo is available
    if ! command -v sudo &> /dev/null; then
        log_error "sudo is required but not installed"
        log_info "Please install sudo or run as root"
        return 1
    fi
    
    # Test sudo access
    if sudo -n true 2>/dev/null; then
        SUDO_CMD="sudo"
        log_info "Sudo access confirmed (passwordless)"
    else
        log_info "Requesting sudo access..."
        if sudo -v; then
            SUDO_CMD="sudo"
            log_info "Sudo access granted"
        else
            log_error "Failed to obtain sudo access"
            return 1
        fi
    fi
}

# Sudo command wrapper (empty if root)
SUDO_CMD=""

# Auto-bootstrap missing dependencies
bootstrap_dependencies() {
    log_section "Auto-bootstrapping Missing Dependencies"
    
    local missing_packages=()
    local package_map=()
    
    # Map commands to package names
    declare -A cmd_to_pkg=(
        ["gcc"]="build-essential"
        ["clang"]="clang"
        ["make"]="build-essential"
        ["cmake"]="cmake"
        ["autoconf"]="autoconf"
        ["automake"]="automake"
        ["libtool"]="libtool-bin"
        ["pkg-config"]="pkg-config"
        ["git"]="git"
        ["nasm"]="nasm"
        ["yasm"]="yasm"
    )
    
    # Check required dependencies
    local required_tools=("gcc" "clang" "make" "cmake" "autoconf" "automake" "libtool" "pkg-config" "git")
    for cmd in "${required_tools[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            local pkg="${cmd_to_pkg[$cmd]}"
            if [ -n "$pkg" ]; then
                missing_packages+=("$pkg")
            else
                missing_packages+=("$cmd")
            fi
        fi
    done
    
    # Install missing packages if any
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log_info "Installing missing dependencies: ${missing_packages[*]}"
        
        if command -v apt &> /dev/null; then
            # Debian/Ubuntu
            $SUDO_CMD apt update || {
                log_error "Failed to update package lists"
                return 1
            }
            $SUDO_CMD apt install -y "${missing_packages[@]}" || {
                log_error "Failed to install dependencies"
                return 1
            }
        elif command -v dnf &> /dev/null; then
            # Fedora/RHEL
            $SUDO_CMD dnf install -y "${missing_packages[@]}" || {
                log_error "Failed to install dependencies"
                return 1
            }
        elif command -v pacman &> /dev/null; then
            # Arch Linux
            $SUDO_CMD pacman -Sy --noconfirm "${missing_packages[@]}" || {
                log_error "Failed to install dependencies"
                return 1
            }
        else
            log_error "No supported package manager found (apt/dnf/pacman)"
            log_error "Please install dependencies manually: ${missing_packages[*]}"
            return 1
        fi
        
        log_info "Dependencies installed successfully"
    else
        log_info "All required dependencies are present"
    fi
}

# Dependency checking (legacy function name for compatibility)
check_dependencies() {
    bootstrap_dependencies
    
    # Check Rust if Rust build is requested
    if [ "$INSTALL_RUST" -eq 1 ] || [ "$INSTALL_ALL" -eq 1 ]; then
        if ! command -v rustc &> /dev/null || ! command -v cargo &> /dev/null; then
            log_warn "Rust not found. Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
            if [ "$INSTALL_RUST" -eq 1 ]; then
                log_error "Rust is required for Rust component installation"
                return 1
            fi
        fi
    fi
    
    # Check kernel version
    local kernel_version=$(uname -r)
    local kernel_major=$(echo "$kernel_version" | cut -d. -f1)
    local kernel_minor=$(echo "$kernel_version" | cut -d. -f2)
    
    if [ "$kernel_major" -lt 5 ] || ([ "$kernel_major" -eq 5 ] && [ "$kernel_minor" -lt 13 ]); then
        log_warn "Kernel $kernel_version < 5.13, some features (Landlock) may not be available"
    else
        log_info "Kernel version: $kernel_version (OK)"
    fi
    
    log_info "All required dependencies present"
    return 0
}

# Load METEOR flags
load_meteor_flags() {
    local flags_file="$SCRIPT_DIR/../../METEOR_TRUE_FLAGS.sh"
    if [ -f "$flags_file" ]; then
        # shellcheck disable=SC1090
        source "$flags_file"
        export CFLAGS="${CFLAGS_OPTIMAL} ${CFLAGS_SECURITY}"
        export CXXFLAGS="${CXXFLAGS_OPTIMAL} ${CFLAGS_SECURITY}"
        export LDFLAGS="${LDFLAGS_OPTIMAL} ${LDFLAGS_SECURITY}"
        log_info "Applied METEOR TRUE OPTIMAL + SECURITY flags"
        return 0
    else
        log_warn "METEOR_TRUE_FLAGS.sh not found at $flags_file, using default hardening flags"
        return 1
    fi
}

# Component installation functions
install_core() {
    log_section "Phase 1: Installing Core Image Libraries"
    
    if checkpoint_exists "core"; then
        log_info "Core libraries already installed (checkpoint exists), skipping"
        return 0
    fi
    
    if [ ! -x "./builders/build.sh" ]; then
        log_error "builders/build.sh not found or not executable"
        return 1
    fi
    
    log_info "Building core image libraries..."
    if IMAGEHARDEN_CPU="$IMAGEHARDEN_CPU" ./builders/build.sh; then
        create_checkpoint "core"
        log_info "Core libraries installed successfully"
        return 0
    else
        log_error "Core library build failed"
        return 1
    fi
}

install_extended() {
    log_section "Phase 2: Installing Extended Format Libraries"
    
    if checkpoint_exists "extended"; then
        log_info "Extended formats already installed (checkpoint exists), skipping"
        return 0
    fi
    
    if [ ! -x "./builders/build_extended_formats.sh" ]; then
        log_error "builders/build_extended_formats.sh not found or not executable"
        return 1
    fi
    
    log_info "Building extended format libraries (AVIF, JXL, TIFF, OpenEXR)..."
    if IMAGEHARDEN_CPU="$IMAGEHARDEN_CPU" ./builders/build_extended_formats.sh; then
        create_checkpoint "extended"
        log_info "Extended format libraries installed successfully"
        return 0
    else
        log_error "Extended format build failed"
        return 1
    fi
}

install_audio() {
    log_section "Phase 3: Installing Audio Codec Libraries"
    
    if checkpoint_exists "audio"; then
        log_info "Audio libraries already installed (checkpoint exists), skipping"
        return 0
    fi
    
    if [ ! -x "./builders/build_audio.sh" ]; then
        log_error "builders/build_audio.sh not found or not executable"
        return 1
    fi
    
    log_info "Building audio codec libraries..."
    if ./builders/build_audio.sh; then
        create_checkpoint "audio"
        log_info "Audio libraries installed successfully"
        return 0
    else
        log_error "Audio library build failed"
        return 1
    fi
}

install_ffmpeg_wasm() {
    log_section "Phase 4: Installing FFmpeg WebAssembly Sandbox"
    
    if checkpoint_exists "ffmpeg_wasm"; then
        log_info "FFmpeg WASM already installed (checkpoint exists), skipping"
        return 0
    fi
    
    if [ ! -x "./builders/setup_emsdk.sh" ]; then
        log_warn "builders/setup_emsdk.sh not found, skipping FFmpeg WASM setup"
        return 0
    fi
    
    if [ ! -x "./builders/build_ffmpeg_wasm.sh" ]; then
        log_warn "builders/build_ffmpeg_wasm.sh not found, skipping FFmpeg WASM build"
        return 0
    fi
    
    log_info "Setting up Emscripten SDK..."
    if ./builders/setup_emsdk.sh; then
        log_info "Building FFmpeg WebAssembly..."
        if ./builders/build_ffmpeg_wasm.sh; then
            create_checkpoint "ffmpeg_wasm"
            log_info "FFmpeg WASM installed successfully"
            return 0
        else
            log_warn "FFmpeg WASM build failed, continuing..."
            return 0
        fi
    else
        log_warn "Emscripten SDK setup failed, skipping FFmpeg WASM"
        return 0
    fi
}

install_drivers() {
    log_section "Phase 5: Installing Hardened Video Drivers"
    
    if checkpoint_exists "drivers"; then
        log_info "Video drivers already configured (checkpoint exists), skipping"
        return 0
    fi
    
    if [ ! -x "./builders/build_hardened_drivers.sh" ]; then
        log_warn "builders/build_hardened_drivers.sh not found, skipping video driver configuration"
        return 0
    fi
    
    log_info "Generating hardened video driver configurations..."
    if ./builders/build_hardened_drivers.sh; then
        create_checkpoint "drivers"
        log_info "Video driver configurations generated successfully"
        return 0
    else
        log_warn "Video driver configuration failed, continuing..."
        return 0
    fi
}

install_audio_drivers() {
    log_section "Phase 6: Installing Hardened Audio Drivers"
    
    if checkpoint_exists "audio_drivers"; then
        log_info "Audio drivers already configured (checkpoint exists), skipping"
        return 0
    fi
    
    if [ ! -x "./builders/build_hardened_audio_drivers.sh" ]; then
        log_warn "builders/build_hardened_audio_drivers.sh not found, skipping audio driver configuration"
        return 0
    fi
    
    log_info "Generating hardened audio driver configurations..."
    if ./builders/build_hardened_audio_drivers.sh; then
        create_checkpoint "audio_drivers"
        log_info "Audio driver configurations generated successfully"
        return 0
    else
        log_warn "Audio driver configuration failed, continuing..."
        return 0
    fi
}

install_rust() {
    log_section "Phase 7: Installing Rust Application"
    
    if checkpoint_exists "rust"; then
        log_info "Rust application already built (checkpoint exists), skipping"
        return 0
    fi
    
    if [ ! -d "./image_harden" ]; then
        log_warn "image_harden directory not found, skipping Rust build"
        return 0
    fi
    
    if ! command -v cargo &> /dev/null; then
        log_error "cargo not found, cannot build Rust application"
        return 1
    fi
    
    log_info "Building Rust application..."
    cd image_harden
    
    if cargo build --release; then
        cd ..
        create_checkpoint "rust"
        log_info "Rust application built successfully"
        return 0
    else
        cd ..
        log_error "Rust build failed"
        return 1
    fi
}

install_tests() {
    log_section "Phase 8: Running Integration Tests"
    
    if checkpoint_exists "tests"; then
        log_info "Tests already run (checkpoint exists), skipping"
        return 0
    fi
    
    if [ ! -x "./builders/integration-tests.sh" ]; then
        log_warn "builders/integration-tests.sh not found, skipping tests"
        return 0
    fi
    
    log_info "Running integration tests..."
    if ./builders/integration-tests.sh; then
        create_checkpoint "tests"
        log_info "Integration tests passed"
        return 0
    else
        log_warn "Integration tests failed, but continuing..."
        return 0
    fi
}

install_benchmark() {
    log_section "Phase 9: Building Benchmark Tools (Optional)"
    
    if checkpoint_exists "benchmark"; then
        log_info "Benchmark already built (checkpoint exists), skipping"
        return 0
    fi
    
    if [ ! -x "./builders/benchmark.sh" ]; then
        log_warn "builders/benchmark.sh not found, skipping benchmark build"
        return 0
    fi
    
    log_info "Building benchmark tools..."
    if ./builders/benchmark.sh; then
        create_checkpoint "benchmark"
        log_info "Benchmark tools built successfully"
        return 0
    else
        log_warn "Benchmark build failed, continuing..."
        return 0
    fi
}

install_sbom() {
    log_section "Phase 10: Generating SBOM (Optional)"
    
    if checkpoint_exists "sbom"; then
        log_info "SBOM already generated (checkpoint exists), skipping"
        return 0
    fi
    
    if [ ! -x "./builders/generate-sbom.sh" ]; then
        log_warn "builders/generate-sbom.sh not found, skipping SBOM generation"
        return 0
    fi
    
    log_info "Generating Software Bill of Materials..."
    if ./builders/generate-sbom.sh; then
        create_checkpoint "sbom"
        log_info "SBOM generated successfully"
        return 0
    else
        log_warn "SBOM generation failed, continuing..."
        return 0
    fi
}

# Interactive menu
show_menu() {
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  IMAGEHARDER Unified Installer${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
    echo "Select components to install:"
    echo ""
    echo "  [1] Core Image Libraries (PNG, JPEG, GIF)"
    echo "  [2] Extended Formats (AVIF, JXL, TIFF, OpenEXR)"
    echo "  [3] Audio Codecs (MP3, Vorbis, Opus, FLAC)"
    echo "  [4] FFmpeg WebAssembly Sandbox"
    echo "  [5] Hardened Video Drivers"
    echo "  [6] Hardened Audio Drivers"
    echo "  [7] Rust Application (image_harden)"
    echo "  [8] Integration Tests"
    echo "  [9] Benchmark Tools (Optional)"
    echo "  [a] Generate SBOM (Optional)"
    echo "  [A] Install All Components"
    echo "  [q] Quit"
    echo ""
    echo -n "Enter selection (multiple selections allowed, e.g., 1,2,3): "
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all|-A)
                INSTALL_ALL=1
                shift
                ;;
            --core|-c)
                INSTALL_CORE=1
                shift
                ;;
            --extended|-e)
                INSTALL_EXTENDED=1
                shift
                ;;
            --audio|-a)
                INSTALL_AUDIO=1
                shift
                ;;
            --ffmpeg-wasm|-f)
                INSTALL_FFMPEG_WASM=1
                shift
                ;;
            --drivers|-d)
                INSTALL_DRIVERS=1
                shift
                ;;
            --audio-drivers|-ad)
                INSTALL_AUDIO_DRIVERS=1
                shift
                ;;
            --rust|-r)
                INSTALL_RUST=1
                shift
                ;;
            --tests|-t)
                INSTALL_TESTS=1
                shift
                ;;
            --benchmark|-b)
                INSTALL_BENCHMARK=1
                shift
                ;;
            --sbom|-s)
                INSTALL_SBOM=1
                shift
                ;;
            --cpu=*)
                IMAGEHARDEN_CPU="${1#*=}"
                shift
                ;;
            --prefix=*)
                INSTALL_PREFIX="${1#*=}"
                shift
                ;;
            --non-interactive|--yes|-y|--no-prompt)
                NON_INTERACTIVE=1
                export NON_INTERACTIVE
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
IMAGEHARDER Unified Installer

Usage: $0 [OPTIONS]

Options:
  --all, -A              Install all components
  --core, -c             Install core image libraries
  --extended, -e         Install extended format libraries
  --audio, -a            Install audio codec libraries
  --ffmpeg-wasm, -f      Install FFmpeg WebAssembly sandbox
  --drivers, -d          Install hardened video drivers
  --audio-drivers, -ad   Install hardened audio drivers
  --rust, -r             Build Rust application
  --tests, -t            Run integration tests
  --benchmark, -b        Build benchmark tools
  --sbom, -s             Generate SBOM
  --cpu=PROFILE          CPU profile (generic, v3, host)
  --prefix=PATH          Installation prefix (default: /usr/local)
  --non-interactive, -y  Run in non-interactive mode (auto-bootstrap deps)
  --help, -h             Show this help message

Environment Variables:
  IMAGEHARDEN_CPU        CPU profile (generic, v3, host)
  INSTALL_PREFIX         Installation prefix
  LOG_FILE               Log file path

Examples:
  # Install all components
  $0 --all

  # Install specific components
  $0 --core --extended --rust

  # Install with CPU profile
  IMAGEHARDEN_CPU=host $0 --all

  # Interactive mode (no arguments)
  $0

EOF
}

# Main installation function
run_installation() {
    log_section "Starting IMAGEHARDER Installation"
    log_info "Installation prefix: $INSTALL_PREFIX"
    log_info "CPU profile: $IMAGEHARDEN_CPU"
    log_info "Log file: $LOG_FILE"
    
    # Check sudo access
    if ! check_sudo; then
        log_error "Sudo check failed"
        return 1
    fi
    
    # Auto-bootstrap dependencies
    if ! bootstrap_dependencies; then
        log_error "Dependency bootstrap failed"
        return 1
    fi
    
    # Load METEOR flags
    load_meteor_flags || true
    
    # Create checkpoint directory
    mkdir -p "$CHECKPOINT_DIR"
    
    # Run installations
    local failed=0
    
    if [ "$INSTALL_ALL" -eq 1 ] || [ "$INSTALL_CORE" -eq 1 ]; then
        if ! install_core; then
            failed=1
        fi
    fi
    
    if [ "$INSTALL_ALL" -eq 1 ] || [ "$INSTALL_EXTENDED" -eq 1 ]; then
        if ! install_extended; then
            failed=1
        fi
    fi
    
    if [ "$INSTALL_ALL" -eq 1 ] || [ "$INSTALL_AUDIO" -eq 1 ]; then
        if ! install_audio; then
            failed=1
        fi
    fi
    
    if [ "$INSTALL_ALL" -eq 1 ] || [ "$INSTALL_FFMPEG_WASM" -eq 1 ]; then
        install_ffmpeg_wasm || true  # Optional, don't fail on error
    fi
    
    if [ "$INSTALL_ALL" -eq 1 ] || [ "$INSTALL_DRIVERS" -eq 1 ]; then
        install_drivers || true  # Optional, don't fail on error
    fi
    
    if [ "$INSTALL_ALL" -eq 1 ] || [ "$INSTALL_AUDIO_DRIVERS" -eq 1 ]; then
        install_audio_drivers || true  # Optional, don't fail on error
    fi
    
    if [ "$INSTALL_ALL" -eq 1 ] || [ "$INSTALL_RUST" -eq 1 ]; then
        if ! install_rust; then
            failed=1
        fi
    fi
    
    if [ "$INSTALL_ALL" -eq 1 ] || [ "$INSTALL_TESTS" -eq 1 ]; then
        install_tests || true  # Optional, don't fail on error
    fi
    
    if [ "$INSTALL_BENCHMARK" -eq 1 ]; then
        install_benchmark || true  # Optional
    fi
    
    if [ "$INSTALL_SBOM" -eq 1 ]; then
        install_sbom || true  # Optional
    fi
    
    return $failed
}

# Installation summary
show_summary() {
    log_section "Installation Summary"
    
    echo "Installation completed at: $(date)"
    echo "Log file: $LOG_FILE"
    echo ""
    
    if [ ${#ERRORS[@]} -gt 0 ]; then
        echo -e "${RED}Errors encountered:${NC}"
        for error in "${ERRORS[@]}"; do
            echo "  - $error"
        done
        echo ""
    fi
    
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Warnings:${NC}"
        for warning in "${WARNINGS[@]}"; do
            echo "  - $warning"
        done
        echo ""
    fi
    
    echo "Next steps:"
    echo "  1. Review installation log: less $LOG_FILE"
    echo "  2. Verify installation: ls -la $INSTALL_PREFIX/lib/lib*"
    echo "  3. Run tests: ./integration-tests.sh"
    echo "  4. Check documentation: cat README.md"
}

# Main execution
main() {
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "IMAGEHARDER Installation Log - $(date)" > "$LOG_FILE"
    
    # Parse arguments
    if [ $# -eq 0 ]; then
        # Interactive mode
        show_menu
        read -r selection
        case "$selection" in
            [1-9aAq]*)
                if [[ "$selection" == *"1"* ]]; then INSTALL_CORE=1; fi
                if [[ "$selection" == *"2"* ]]; then INSTALL_EXTENDED=1; fi
                if [[ "$selection" == *"3"* ]]; then INSTALL_AUDIO=1; fi
                if [[ "$selection" == *"4"* ]]; then INSTALL_FFMPEG_WASM=1; fi
                if [[ "$selection" == *"5"* ]]; then INSTALL_DRIVERS=1; fi
                if [[ "$selection" == *"6"* ]]; then INSTALL_AUDIO_DRIVERS=1; fi
                if [[ "$selection" == *"7"* ]]; then INSTALL_RUST=1; fi
                if [[ "$selection" == *"8"* ]]; then INSTALL_TESTS=1; fi
                if [[ "$selection" == *"9"* ]]; then INSTALL_BENCHMARK=1; fi
                if [[ "$selection" == *"a"* ]]; then INSTALL_SBOM=1; fi
                if [[ "$selection" == *"A"* ]]; then INSTALL_ALL=1; fi
                if [[ "$selection" == *"q"* ]]; then exit 0; fi
                ;;
            *)
                log_error "Invalid selection"
                exit 1
                ;;
        esac
    else
        parse_args "$@"
    fi
    
    # Check if anything is selected
    if [ "$INSTALL_ALL" -eq 0 ] && \
       [ "$INSTALL_CORE" -eq 0 ] && \
       [ "$INSTALL_EXTENDED" -eq 0 ] && \
       [ "$INSTALL_AUDIO" -eq 0 ] && \
       [ "$INSTALL_FFMPEG_WASM" -eq 0 ] && \
       [ "$INSTALL_DRIVERS" -eq 0 ] && \
       [ "$INSTALL_AUDIO_DRIVERS" -eq 0 ] && \
       [ "$INSTALL_RUST" -eq 0 ] && \
       [ "$INSTALL_TESTS" -eq 0 ] && \
       [ "$INSTALL_BENCHMARK" -eq 0 ] && \
       [ "$INSTALL_SBOM" -eq 0 ]; then
        log_error "No components selected for installation"
        show_help
        exit 1
    fi
    
    # Run installation
    if run_installation; then
        show_summary
        log_info "Installation completed successfully"
        exit 0
    else
        show_summary
        log_error "Installation completed with errors"
        exit 1
    fi
}

# Run main function
main "$@"

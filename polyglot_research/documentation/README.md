# Documentation Index

Complete technical documentation for the TeamTNT polyglot research package.

---

## Available Documentation

### 1. POLYGLOT_ANALYSIS.md (18 KB)
**Comprehensive Threat Intelligence Report**

**Contents:**
- Executive Summary
- Threat Actor Background (APT TeamTNT)
- Technical Deep Dive
  - GIF polyglot structure
  - PNG polyglot structure
  - JPEG polyglot structure
- Attack Scenarios
  - Cloud infrastructure compromise
  - Container escape
  - Email attachment bypass
- Detection Methods
  - Magic byte + shebang detection
  - Strict image validation
  - File permission monitoring
  - Content analysis
- YARA Rules
  - APT_TeamTNT_Polyglot_GIF
  - APT_TeamTNT_Polyglot_PNG
  - APT_TeamTNT_Polyglot_JPEG
  - Generic_Image_Polyglot
- IOCs and Signatures
  - **TeamTNT XMR wallet addresses (for Chainalysis blacklisting)**
  - C2 domains
  - Mining pools
  - File hashes
- Mitigation Strategies
  - IMAGEHARDER deployment
  - File upload security
  - Cloud storage security
  - Endpoint protection
  - Container security
- Proof of Concept Usage
- References

**Key Sections for VX Underground:**
- IOCs with XMR addresses (page 15)
- YARA detection rules (page 11)
- Attack scenarios (page 8)

---

### 2. ASM_IMPLEMENTATION.md (15 KB)
**x86-64 Assembly Technical Deep Dive**

**Contents:**
- Overview and Features
- Build Instructions
- Usage Examples
- Technical Deep Dive
  - Memory layout
  - Syscall interface
  - Code flow diagrams
- GIF Generation Algorithm (assembly-level)
- PNG Generation Algorithm (assembly-level)
- JPEG Generation Algorithm (assembly-level)
- Advantages Over C Version
  - Size comparison (~2KB vs ~20KB)
  - Dependency comparison (zero vs libc)
  - Execution speed benchmarks
- Instruction Breakdown
  - String comparison (strcmp)
  - File reading
  - Position-independent code (PIC)
- Security Considerations
  - ASLR compatibility
  - Stack protection
  - NX stack verification
- Debugging
  - GDB session examples
  - Strace syscall tracing
  - Hexdump output verification
- Performance Optimization
- Comparison with Real Malware
- Future Enhancements
- References

**Key Sections for Researchers:**
- Syscall interface (page 3)
- Algorithm breakdowns (pages 5-7)
- Debugging guide (page 11)

---

## Reading Guide

### For Security Researchers
**Start here:**
1. ../README.md - Overview and quick start
2. POLYGLOT_ANALYSIS.md - Complete threat analysis
3. ../defense/CVE_COVERAGE.md - Defense strategies

### For Malware Analysts
**Start here:**
1. POLYGLOT_ANALYSIS.md (sections: Technical Deep Dive, IOCs)
2. ASM_IMPLEMENTATION.md (sections: Memory Layout, Syscall Interface)
3. POLYGLOT_ANALYSIS.md (section: YARA Rules)

### For Developers
**Start here:**
1. ../README.md - Quick start
2. ../c_implementation/polyglot_generator.c - Source code
3. ASM_IMPLEMENTATION.md - Low-level implementation

### For VX Underground Publication
**Include these sections:**
1. Complete POLYGLOT_ANALYSIS.md
2. IOCs section with XMR addresses
3. YARA detection rules
4. ASM_IMPLEMENTATION.md (demonstrates minimalist approach)
5. Source code (both C and Assembly)

---

## Document Sizes

| Document | Size | Lines | Format |
|----------|------|-------|--------|
| POLYGLOT_ANALYSIS.md | 18 KB | 850+ | Markdown |
| ASM_IMPLEMENTATION.md | 15 KB | 700+ | Markdown |
| ../defense/CVE_COVERAGE.md | 7 KB | 450+ | Markdown |
| **Total Documentation** | **40 KB** | **2000+** | - |

---

## Key Information Quick Reference

### TeamTNT XMR Wallets (Blacklist These)
See **POLYGLOT_ANALYSIS.md**, section "IOCs and Signatures" for complete list:
- Primary wallet: `41ybR4WpWqEnpJdh7GpSs2dGYFLzT4XDw9nWdC66sGViu...`
- Secondary wallets: 4 additional addresses
- Mining pools: pool.supportxmr.com, pool.minexmr.com, gulf.moneroocean.stream

### Detection Signatures
See **POLYGLOT_ANALYSIS.md**, section "YARA Rules":
- 4 complete YARA rules for all polyglot types
- Ready to deploy in production

### CVE Mitigations
See **../defense/CVE_COVERAGE.md**:
- CVE-2015-8540 (libpng): Buffer overflow
- CVE-2019-7317 (libpng): Use-after-free
- CVE-2018-14498 (libjpeg): Heap over-read
- CVE-2019-15133 (giflib): Out-of-bounds read
- CVE-2016-3977 (giflib): Buffer overflow

### Build Sizes
See **ASM_IMPLEMENTATION.md**, section "Advantages Over C Version":
- C version: ~20 KB
- Assembly version: ~2 KB (10x smaller)
- Assembly + UPX: ~1.5 KB

---

## Cross-References

**From POLYGLOT_ANALYSIS.md to other docs:**
- Detection using IMAGEHARDER → ../defense/CVE_COVERAGE.md
- Assembly implementation details → ASM_IMPLEMENTATION.md
- Source code examples → ../c_implementation/, ../asm_implementation/

**From ASM_IMPLEMENTATION.md to other docs:**
- C version comparison → ../c_implementation/polyglot_generator.c
- Threat intelligence context → POLYGLOT_ANALYSIS.md
- Defense strategies → ../defense/CVE_COVERAGE.md

**From CVE_COVERAGE.md to other docs:**
- Polyglot detection → POLYGLOT_ANALYSIS.md
- Implementation details → ../c_implementation/, ../asm_implementation/

---

## Updates and Maintenance

**Last Updated:** 2025-01-08
**Version:** 1.0.0
**Maintained by:** IMAGEHARDER Security Research Team

**Update Frequency:**
- IOCs: Updated when new TeamTNT infrastructure discovered
- YARA rules: Updated for new evasion techniques
- CVE coverage: Updated when new vulnerabilities disclosed

**Contributing:**
- Submit new IOCs via GitHub issues
- Propose YARA rule improvements via pull requests
- Report documentation errors via issues

---

## License

All documentation is provided under MIT License for educational purposes.

**Disclaimer:** This research is provided for authorized security research only. Unauthorized use for malicious purposes is strictly prohibited and may be illegal in your jurisdiction.

---

## Contact

**Security Research:** security@imageharder.io
**Threat Intelligence:** iocs@imageharder.io
**VX Underground:** https://vx-underground.org/
**GitHub:** https://github.com/SWORDIntel/IMAGEHARDER

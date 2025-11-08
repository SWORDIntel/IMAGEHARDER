# TeamTNT Polyglot Research Package
# ======================================
#
# Complete analysis and implementation of APT TeamTNT's polyglot file technique
# For publication to VX Underground Malware Archive
#
# Author: IMAGEHARDER Security Research Team
# Date: 2025-01-08
# License: MIT (Educational Use Only)

.PHONY: all c asm test clean help

all: c asm

# Build C implementation
c:
	@echo "Building C polyglot generator..."
	@$(MAKE) -C c_implementation all

# Build Assembly implementation
asm:
	@echo "Building Assembly polyglot generator..."
	@cd asm_implementation && ./build_asm.sh

# Run comprehensive tests
test: all
	@echo "Testing C implementation..."
	@$(MAKE) -C c_implementation test
	@echo ""
	@echo "Testing Assembly implementation..."
	@cd asm_implementation && \
	./polyglot_gen_asm gif ../examples/example_payload.sh test_asm.gif && \
	./polyglot_gen_asm png ../examples/example_payload.sh test_asm.png && \
	./polyglot_gen_asm jpeg ../examples/example_payload.sh test_asm.jpg && \
	file test_asm.* && \
	chmod +x test_asm.gif && ./test_asm.gif

# Clean all build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@$(MAKE) -C c_implementation clean
	@rm -f asm_implementation/polyglot_gen_asm
	@rm -f asm_implementation/polyglot_gen_asm.o
	@rm -f asm_implementation/test_asm.*
	@echo "Clean complete."

# Show help
help:
	@echo "TeamTNT Polyglot Research Package"
	@echo "=================================="
	@echo ""
	@echo "Targets:"
	@echo "  make all     - Build both C and Assembly implementations"
	@echo "  make c       - Build C implementation only"
	@echo "  make asm     - Build Assembly implementation only"
	@echo "  make test    - Build and run tests for both"
	@echo "  make clean   - Remove all build artifacts"
	@echo "  make help    - Show this help message"
	@echo ""
	@echo "Directory Structure:"
	@echo "  c_implementation/    - C version with Makefile"
	@echo "  asm_implementation/  - x86-64 assembly version"
	@echo "  documentation/       - Complete technical docs"
	@echo "  examples/            - Example payloads"
	@echo "  defense/             - CVE mitigations & IMAGEHARDER"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make all"
	@echo "  2. ./c_implementation/polyglot_gen -t gif -s examples/example_payload.sh -o test.gif"
	@echo "  3. ./asm_implementation/polyglot_gen_asm gif examples/example_payload.sh test.gif"
	@echo ""

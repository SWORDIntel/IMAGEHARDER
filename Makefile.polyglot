# Makefile for Polyglot Generator
# Educational Security Research Tool

CC = gcc
CFLAGS = -Wall -Wextra -O2 -std=c11
TARGET = polyglot_gen
SOURCE = polyglot_generator.c

.PHONY: all clean test demo install

all: $(TARGET)

$(TARGET): $(SOURCE)
	@echo "[+] Compiling polyglot generator..."
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCE)
	@echo "[✓] Build complete: ./$(TARGET)"

test: $(TARGET)
	@echo "[*] Running tests..."
	@echo "[1/3] Generating GIF polyglot..."
	./$(TARGET) -t gif -s example_payload.sh -o test_output.gif -v
	@echo ""
	@echo "[2/3] Generating PNG polyglot..."
	./$(TARGET) -t png -s example_payload.sh -o test_output.png -v
	@echo ""
	@echo "[3/3] Generating JPEG polyglot..."
	./$(TARGET) -t jpeg -s example_payload.sh -o test_output.jpg -v
	@echo ""
	@echo "[*] Verifying with 'file' command:"
	file test_output.gif test_output.png test_output.jpg
	@echo ""
	@echo "[*] Testing execution (GIF):"
	chmod +x test_output.gif
	./test_output.gif
	@echo ""
	@echo "[✓] All tests passed!"

demo: $(TARGET)
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║       Polyglot Generator - Interactive Demo             ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Creating polyglot files from example_payload.sh..."
	@echo ""
	./$(TARGET) -t gif -s example_payload.sh -o demo.gif
	./$(TARGET) -t png -s example_payload.sh -o demo.png
	./$(TARGET) -t jpeg -s example_payload.sh -o demo.jpg
	@echo ""
	@echo "Files created:"
	@ls -lh demo.gif demo.png demo.jpg
	@echo ""
	@echo "Verification:"
	@file demo.gif demo.png demo.jpg
	@echo ""
	@echo "Try executing: chmod +x demo.gif && ./demo.gif"
	@echo ""

validate: test
	@echo "[*] Testing detection with IMAGEHARDER..."
	@if [ -x ./image_harden/target/release/image_harden_cli ]; then \
		echo "Testing GIF polyglot detection:"; \
		./image_harden/target/release/image_harden_cli test_output.gif || echo "✓ Polyglot correctly detected and rejected!"; \
		echo ""; \
		echo "Testing PNG polyglot detection:"; \
		./image_harden/target/release/image_harden_cli test_output.png || echo "✓ Polyglot correctly detected and rejected!"; \
		echo ""; \
		echo "Testing JPEG polyglot detection:"; \
		./image_harden/target/release/image_harden_cli test_output.jpg || echo "✓ Polyglot correctly detected and rejected!"; \
	else \
		echo "[!] IMAGEHARDER not built. Run 'cd image_harden && cargo build --release' first."; \
	fi

install: $(TARGET)
	@echo "[+] Installing to /usr/local/bin..."
	install -m 755 $(TARGET) /usr/local/bin/
	@echo "[✓] Installed: /usr/local/bin/$(TARGET)"

clean:
	@echo "[*] Cleaning build artifacts..."
	rm -f $(TARGET)
	rm -f test_output.* demo.*
	@echo "[✓] Clean complete"

help:
	@echo "Polyglot Generator - Makefile Help"
	@echo ""
	@echo "Targets:"
	@echo "  make all       - Build the polyglot generator"
	@echo "  make test      - Build and run comprehensive tests"
	@echo "  make demo      - Create demo polyglot files"
	@echo "  make validate  - Test detection with IMAGEHARDER"
	@echo "  make install   - Install to /usr/local/bin (requires sudo)"
	@echo "  make clean     - Remove build artifacts"
	@echo "  make help      - Show this help message"
	@echo ""
	@echo "Usage Examples:"
	@echo "  ./polyglot_gen -t gif -s payload.sh -o evil.gif"
	@echo "  ./polyglot_gen -t png -s payload.sh -o evil.png"
	@echo "  ./polyglot_gen -t jpeg -s payload.sh -o evil.jpg"
	@echo ""

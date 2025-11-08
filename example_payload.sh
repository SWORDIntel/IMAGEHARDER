#!/bin/sh
# Example Benign Payload for Polyglot Testing
# DO NOT use malicious payloads - this is for security research only

echo "================================================"
echo "POLYGLOT FILE EXECUTED"
echo "================================================"
echo "Timestamp: $(date)"
echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo "Working Directory: $(pwd)"
echo "================================================"
echo ""
echo "System Information:"
uname -a
echo ""
echo "This demonstrates that a file can be both:"
echo "  1. A valid image (viewable in image viewers)"
echo "  2. An executable shell script"
echo ""
echo "Detection should flag this as suspicious!"
echo "================================================"

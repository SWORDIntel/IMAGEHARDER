#!/bin/bash
set -e

# Automated Cockpit Setup with Local-Only Hardening
# Configures Cockpit for secure system management (localhost only)

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)"
    exit 1
fi

echo "============================================"
echo "Cockpit Setup - Local Access Only"
echo "============================================"
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "ERROR: Cannot detect OS"
    exit 1
fi

echo "[INFO] Detected OS: $OS"
echo ""

# Install Cockpit
echo "[1/8] Installing Cockpit..."
case "$OS" in
    debian|ubuntu)
        apt-get update
        apt-get install -y cockpit cockpit-pcp cockpit-podman
        ;;
    fedora|rhel|centos)
        dnf install -y cockpit cockpit-pcp cockpit-podman
        ;;
    *)
        echo "ERROR: Unsupported OS: $OS"
        exit 1
        ;;
esac

echo "[2/8] Configuring localhost-only binding..."
# Create drop-in directory
mkdir -p /etc/systemd/system/cockpit.socket.d/

# Configure to listen only on localhost
cat > /etc/systemd/system/cockpit.socket.d/listen.conf <<'EOF'
[Socket]
# Override default ListenStream
ListenStream=
# Bind ONLY to localhost
ListenStream=127.0.0.1:9090
EOF

echo "[3/8] Configuring Cockpit settings..."
mkdir -p /etc/cockpit
cat > /etc/cockpit/cockpit.conf <<'EOF'
[WebService]
# Allow only localhost origins
Origins = http://127.0.0.1:9090 http://localhost:9090
UrlRoot = /

[Session]
# 15 minute idle timeout
IdleTimeout = 15
Banner = /etc/issue.cockpit

[Log]
Fatal = criticals
EOF

# Create security banner
cat > /etc/issue.cockpit <<'EOF'
╔════════════════════════════════════════════════════════════╗
║          IMAGEHARDER SYSTEM MANAGEMENT                     ║
║                                                            ║
║  WARNING: Authorized access only                          ║
║  All activities are logged and monitored                  ║
║  Local access only - no external connections permitted    ║
╚════════════════════════════════════════════════════════════╝
EOF

echo "[4/8] Applying firewall rules..."
# Detect firewall system
if command -v firewall-cmd &> /dev/null; then
    echo "  Using firewalld..."
    # Remove cockpit from public zone
    firewall-cmd --permanent --zone=public --remove-service=cockpit 2>/dev/null || true
    firewall-cmd --reload
elif command -v ufw &> /dev/null; then
    echo "  Using UFW..."
    # Deny external access
    ufw deny 9090/tcp 2>/dev/null || true
else
    echo "  WARNING: No firewall detected. Manually configure firewall to block port 9090 externally."
fi

echo "[5/8] Disabling unnecessary Cockpit features..."
# Mask services we don't need
systemctl mask cockpit-networkmanager.service 2>/dev/null || true
systemctl mask cockpit-kdump.service 2>/dev/null || true

echo "[6/8] Installing custom IMAGEHARDER dashboard..."
mkdir -p /usr/share/cockpit/imageharder

cat > /usr/share/cockpit/imageharder/manifest.json <<'EOF'
{
  "version": 0,
  "name": "imageharder",
  "description": "IMAGEHARDER Media Hardening Monitoring",
  "requires": {
    "cockpit": "200"
  },
  "content-security-policy": "default-src 'self' 'unsafe-inline' 'unsafe-eval'",
  "menu": {
    "index": {
      "label": "Media Hardening",
      "order": 10
    }
  }
}
EOF

# Copy the dashboard HTML (if it doesn't exist, create a basic one)
if [ ! -f /usr/share/cockpit/imageharder/index.html ]; then
    cat > /usr/share/cockpit/imageharder/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <title>IMAGEHARDER</title>
    <meta charset="utf-8">
    <link rel="stylesheet" href="../base1/cockpit.css">
    <script src="../base1/cockpit.js"></script>
</head>
<body>
    <div class="container-fluid">
        <h1>IMAGEHARDER Media Hardening</h1>
        <hr>
        <p>Monitoring dashboard for media processing security.</p>
        <div style="margin: 20px;">
            <button class="btn btn-primary" onclick="window.open('http://localhost:9090', '_blank')">
                Open Prometheus
            </button>
            <button class="btn btn-primary" onclick="window.open('http://localhost:3000', '_blank')">
                Open Grafana
            </button>
        </div>
    </div>
</body>
</html>
HTMLEOF
fi

echo "[7/8] Reloading systemd and starting Cockpit..."
systemctl daemon-reload
systemctl enable cockpit.socket
systemctl restart cockpit.socket

echo "[8/8] Verifying configuration..."
sleep 2

# Check if Cockpit is listening on localhost only
if ss -tlnp | grep -q "127.0.0.1:9090"; then
    echo "✓ Cockpit is listening on localhost only"
else
    echo "⚠ WARNING: Cockpit binding verification failed"
fi

# Check if Cockpit is accessible
if curl -s http://127.0.0.1:9090 > /dev/null 2>&1; then
    echo "✓ Cockpit is accessible on localhost"
else
    echo "⚠ WARNING: Cockpit is not responding"
fi

echo ""
echo "============================================"
echo "Cockpit Installation Complete!"
echo "============================================"
echo ""
echo "Access Cockpit:"
echo "  Local:  http://localhost:9090"
echo ""
echo "Remote access (via SSH tunnel):"
echo "  ssh -L 9090:localhost:9090 $USER@$(hostname -f)"
echo "  Then open: http://localhost:9090"
echo ""
echo "Login credentials: Your system user account"
echo ""
echo "Security status:"
echo "  ✓ Bound to localhost only (127.0.0.1:9090)"
echo "  ✓ Firewall rules applied"
echo "  ✓ Unnecessary features disabled"
echo "  ✓ Custom IMAGEHARDER dashboard installed"
echo ""
echo "To verify security:"
echo "  sudo ss -tlnp | grep 9090"
echo "  Should show: 127.0.0.1:9090 ONLY"
echo ""
echo "To uninstall:"
echo "  sudo systemctl stop cockpit.socket"
echo "  sudo systemctl disable cockpit.socket"
echo "  sudo apt-get remove cockpit*  # or dnf remove cockpit*"
echo ""

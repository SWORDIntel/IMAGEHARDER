# Cockpit Integration Guide

**Red Hat Cockpit** integration for IMAGEHARDER provides a web-based interface for system management and monitoring. This guide configures Cockpit with **local-only access** (no external connections) for maximum security.

## Security Posture

**⚠️ LOCAL ACCESS ONLY ⚠️**

Cockpit will be configured to:
- Listen ONLY on localhost (127.0.0.1)
- Require firewall rules blocking external access
- Use strong TLS if accessed via SSH tunnel
- Integrate with existing Prometheus metrics
- Provide read-only views where possible

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Local Machine                        │
│                                                           │
│  ┌──────────┐         ┌──────────┐      ┌────────────┐  │
│  │  Cockpit │◄────────┤ Prometheus│◄─────┤   Media    │  │
│  │  WebUI   │         │  :9090    │      │ Processor  │  │
│  │  :9090   │         └───────────┘      │   :8080    │  │
│  └──────────┘                            └────────────┘  │
│       ▲                                                   │
│       │ localhost only (127.0.0.1)                       │
│       │                                                   │
│  ┌────┴──────────────┐                                   │
│  │  Local Browser    │                                   │
│  │  or SSH Tunnel    │                                   │
│  └───────────────────┘                                   │
└─────────────────────────────────────────────────────────┘

Remote Access (if needed):
  ssh -L 9090:localhost:9090 user@server
```

## Installation

### Debian/Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y cockpit cockpit-pcp cockpit-podman
```

### Fedora/RHEL/CentOS

```bash
sudo dnf install -y cockpit cockpit-pcp cockpit-podman
```

### Enable Service

```bash
sudo systemctl enable --now cockpit.socket
```

## Hardened Configuration

### 1. Bind to Localhost Only

Create `/etc/systemd/system/cockpit.socket.d/listen.conf`:

```ini
[Socket]
# Override default ListenStream
ListenStream=
# Bind ONLY to localhost
ListenStream=127.0.0.1:9090
# Disable IPv6 (optional)
# ListenStream=[::1]:9090
```

Apply changes:

```bash
sudo systemctl daemon-reload
sudo systemctl restart cockpit.socket
```

### 2. Firewall Rules (Defense in Depth)

Even though Cockpit binds to localhost, add firewall rules as defense-in-depth:

**Using firewalld (Fedora/RHEL/CentOS):**

```bash
# Remove cockpit from public zone if present
sudo firewall-cmd --permanent --zone=public --remove-service=cockpit

# Ensure only loopback can access
sudo firewall-cmd --permanent --zone=trusted --add-interface=lo
sudo firewall-cmd --reload
```

**Using UFW (Debian/Ubuntu):**

```bash
# Deny external access to Cockpit
sudo ufw deny 9090/tcp

# Verify localhost still works
curl http://127.0.0.1:9090
```

**Using iptables (manual):**

```bash
# Drop external connections to Cockpit
sudo iptables -A INPUT -p tcp --dport 9090 -i lo -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9090 -j DROP

# Make persistent
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

### 3. Configure Cockpit Settings

Edit `/etc/cockpit/cockpit.conf`:

```ini
[WebService]
# Allow only localhost origins
Origins = http://127.0.0.1:9090 http://localhost:9090
# Require HTTPS for remote access (via SSH tunnel)
UrlRoot = /

# Disable password authentication (use SSH keys only)
[Session]
IdleTimeout = 15
Banner = /etc/issue.cockpit

[Log]
Fatal = criticals
```

Create custom banner `/etc/issue.cockpit`:

```
╔════════════════════════════════════════════════════════════╗
║          IMAGEHARDER SYSTEM MANAGEMENT                     ║
║                                                            ║
║  WARNING: Authorized access only                          ║
║  All activities are logged and monitored                  ║
║  Local access only - no external connections permitted    ║
╚════════════════════════════════════════════════════════════╝
```

### 4. Disable Unnecessary Features

```bash
# Disable network configuration (not needed)
sudo systemctl mask cockpit-networkmanager.service

# Disable kdump (not needed for containers)
sudo systemctl mask cockpit-kdump.service
```

## Prometheus Integration

### Install Cockpit PCP Plugin

```bash
sudo apt-get install -y cockpit-pcp  # Debian/Ubuntu
sudo dnf install -y cockpit-pcp      # Fedora/RHEL
```

### Configure PCP to Scrape Prometheus

Create `/etc/pcp/pmlogger/control.d/prometheus`:

```
# Prometheus metrics collection
prometheus  n   n   PCP_LOG_DIR/prometheus  -r -T24h10m -c config.prometheus
```

Create `/var/lib/pcp/config/pmlogger/config.prometheus`:

```
log mandatory on every 10 seconds {
    # Prometheus metrics from media processor
    prometheus.media_hardening_media_processor_files_processed_total
    prometheus.media_hardening_media_processor_security_violations_total
    prometheus.media_hardening_media_processor_memory_bytes
    prometheus.media_hardening_media_processor_cpu_seconds_total
}
```

### Configure Prometheus as PCP Source

Edit `/etc/pcp/pmcd/pmcd.conf` and add:

```
# Prometheus PMDA
prometheus 144 pipe binary /usr/libexec/pcp/pmdas/prometheus/pmdaprometheus http://localhost:8080/metrics
```

Restart PCP:

```bash
sudo systemctl restart pmcd pmlogger
```

## Accessing Cockpit

### Local Access

Open browser on the local machine:

```
http://localhost:9090
```

Login with your system user credentials.

### Remote Access (SSH Tunnel)

From your remote machine:

```bash
# Create SSH tunnel
ssh -L 9090:localhost:9090 user@your-server

# Keep tunnel open in background
ssh -f -N -L 9090:localhost:9090 user@your-server

# Access via browser
http://localhost:9090
```

**With autossh (persistent tunnel):**

```bash
autossh -M 0 -f -N -L 9090:localhost:9090 user@your-server
```

## Custom Dashboard for IMAGEHARDER

### Install Custom Cockpit Page

Create `/usr/share/cockpit/imageharder/manifest.json`:

```json
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
```

Create `/usr/share/cockpit/imageharder/index.html`:

```html
<!DOCTYPE html>
<html>
<head>
    <title>IMAGEHARDER Monitoring</title>
    <meta charset="utf-8">
    <link rel="stylesheet" href="../base1/cockpit.css">
    <script src="../base1/cockpit.js"></script>
    <style>
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin: 20px;
        }
        .metric-card {
            background: #fff;
            border: 1px solid #ddd;
            border-radius: 4px;
            padding: 15px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .metric-title {
            font-size: 14px;
            color: #666;
            margin-bottom: 5px;
        }
        .metric-value {
            font-size: 32px;
            font-weight: bold;
            color: #333;
        }
        .metric-value.success { color: #28a745; }
        .metric-value.warning { color: #ffc107; }
        .metric-value.danger { color: #dc3545; }
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 5px;
        }
        .status-ok { background-color: #28a745; }
        .status-warning { background-color: #ffc107; }
        .status-error { background-color: #dc3545; }
    </style>
</head>
<body>
    <div class="container-fluid">
        <h1>IMAGEHARDER Media Hardening Monitor</h1>
        <hr>

        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-title">
                    <span class="status-indicator status-ok"></span>
                    Service Status
                </div>
                <div class="metric-value success" id="service-status">Running</div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Files Processed (Total)</div>
                <div class="metric-value" id="files-processed">-</div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Security Violations</div>
                <div class="metric-value danger" id="security-violations">-</div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Memory Usage</div>
                <div class="metric-value" id="memory-usage">-</div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Files Failed</div>
                <div class="metric-value warning" id="files-failed">-</div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Malware Detected</div>
                <div class="metric-value danger" id="malware-detected">-</div>
            </div>
        </div>

        <hr>

        <h2>Quick Actions</h2>
        <div style="margin: 20px;">
            <button class="btn btn-primary" onclick="openPrometheus()">
                Open Prometheus
            </button>
            <button class="btn btn-primary" onclick="openGrafana()">
                Open Grafana
            </button>
            <button class="btn btn-default" onclick="refreshMetrics()">
                Refresh Metrics
            </button>
        </div>

        <h2>Logs</h2>
        <div style="margin: 20px;">
            <button class="btn btn-default" onclick="viewLogs()">
                View Container Logs
            </button>
        </div>
    </div>

    <script>
        // Fetch metrics from Prometheus
        async function fetchMetrics() {
            try {
                const response = await fetch('http://localhost:8080/metrics');
                const text = await response.text();

                // Parse Prometheus text format
                const lines = text.split('\n');
                const metrics = {};

                lines.forEach(line => {
                    if (line.startsWith('#') || !line.trim()) return;

                    const match = line.match(/^([a-zA-Z_:][a-zA-Z0-9_:]*){?([^}]*)}?\s+([0-9.]+)/);
                    if (match) {
                        metrics[match[1]] = parseFloat(match[3]);
                    }
                });

                return metrics;
            } catch (e) {
                console.error('Failed to fetch metrics:', e);
                return {};
            }
        }

        async function updateDashboard() {
            const metrics = await fetchMetrics();

            document.getElementById('files-processed').textContent =
                (metrics['media_hardening_media_processor_files_processed_total'] || 0).toFixed(0);

            document.getElementById('security-violations').textContent =
                (metrics['media_hardening_media_processor_security_violations_total'] || 0).toFixed(0);

            const memBytes = metrics['media_hardening_media_processor_memory_bytes'] || 0;
            const memMB = (memBytes / 1024 / 1024).toFixed(1);
            document.getElementById('memory-usage').textContent = memMB + ' MB';

            document.getElementById('files-failed').textContent =
                (metrics['media_hardening_media_processor_files_failed_total'] || 0).toFixed(0);

            document.getElementById('malware-detected').textContent =
                (metrics['media_hardening_media_processor_malware_detected_total'] || 0).toFixed(0);
        }

        function openPrometheus() {
            window.open('http://localhost:9090', '_blank');
        }

        function openGrafana() {
            window.open('http://localhost:3000', '_blank');
        }

        function refreshMetrics() {
            updateDashboard();
        }

        function viewLogs() {
            // Open Cockpit's log viewer for the container
            window.location.href = '/system/logs#/?tag=media-processor';
        }

        // Update dashboard every 10 seconds
        updateDashboard();
        setInterval(updateDashboard, 10000);
    </script>
</body>
</html>
```

Restart Cockpit:

```bash
sudo systemctl restart cockpit.socket
```

## Monitoring Features

### Available Dashboards

1. **Overview**: System health, CPU, memory, disk
2. **Logs**: Journald logs with filtering
3. **Podman**: Docker/Podman container management
4. **Performance Co-Pilot**: Historical metrics
5. **IMAGEHARDER** (custom): Media processing metrics

### Key Metrics Visible

From Cockpit, you can monitor:

- System resource usage (CPU, RAM, disk)
- Container status and logs
- Media processor statistics (via custom page)
- Network traffic (localhost only)
- System services status

## Security Best Practices

### 1. Keep Cockpit Updated

```bash
sudo apt-get update && sudo apt-get upgrade cockpit  # Debian
sudo dnf update cockpit                               # Fedora
```

### 2. Use SSH Key Authentication Only

Disable password auth in `/etc/ssh/sshd_config`:

```
PasswordAuthentication no
PubkeyAuthentication yes
```

### 3. Monitor Cockpit Access

```bash
# View Cockpit access logs
sudo journalctl -u cockpit.service -f

# View authentication attempts
sudo journalctl | grep cockpit | grep -i auth
```

### 4. Regular Security Audits

```bash
# Check listening ports
sudo ss -tlnp | grep 9090
# Should show: 127.0.0.1:9090 ONLY

# Verify firewall rules
sudo firewall-cmd --list-all  # firewalld
sudo ufw status verbose       # ufw
```

### 5. Limit User Access

Only allow specific users to access Cockpit:

```bash
# Add users to cockpit-ws group
sudo usermod -a -G cockpit-ws username

# Restrict in PAM
# Edit /etc/pam.d/cockpit
# Add: auth required pam_listfile.so item=group sense=allow file=/etc/cockpit-users
```

## Troubleshooting

### Cockpit Not Starting

```bash
# Check status
sudo systemctl status cockpit.socket

# Check logs
sudo journalctl -u cockpit.socket -xe

# Verify configuration
sudo cockpit-ws --no-tls --address=127.0.0.1 --port=9090
```

### Can't Access from Browser

```bash
# Verify listening address
sudo netstat -tlnp | grep 9090

# Test locally
curl http://127.0.0.1:9090

# Check firewall
sudo firewall-cmd --list-all
```

### Metrics Not Showing

```bash
# Verify Prometheus is running
curl http://localhost:8080/metrics

# Check PCP status
sudo systemctl status pmcd pmlogger

# Restart PCP
sudo systemctl restart pmcd pmlogger cockpit.socket
```

### SSH Tunnel Issues

```bash
# Test SSH connection
ssh -v user@server

# Test tunnel
ssh -v -L 9090:localhost:9090 user@server

# Check for port conflicts
lsof -i :9090
```

## Uninstalling Cockpit

If you decide not to use Cockpit:

```bash
# Stop and disable
sudo systemctl stop cockpit.socket
sudo systemctl disable cockpit.socket

# Remove packages
sudo apt-get remove --purge cockpit cockpit-*  # Debian
sudo dnf remove cockpit cockpit-*               # Fedora

# Remove data
sudo rm -rf /var/lib/cockpit
sudo rm -rf /etc/cockpit
```

## Additional Resources

- [Cockpit Documentation](https://cockpit-project.org/guide/latest/)
- [Cockpit Security Guide](https://cockpit-project.org/guide/latest/https.html)
- [Performance Co-Pilot](https://pcp.io/)
- [Prometheus PCP Integration](https://github.com/performancecopilot/pcp)

---

**Security Reminder**: Cockpit is configured for LOCAL ACCESS ONLY. Never expose port 9090 to external networks. Always use SSH tunnels for remote access.

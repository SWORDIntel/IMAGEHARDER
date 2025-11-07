# Production Deployment Guide

## SystemD Service Templates for Sandboxed Media Processing

### Hardened Media Processor Service

```ini
[Unit]
Description=Hardened Media Processor (Images/Audio/Video)
After=network.target

[Service]
Type=simple
User=media-processor
Group=media-processor
WorkingDirectory=/opt/media-processor

# Hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=yes
LockPersonality=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
RemoveIPC=yes
PrivateMounts=yes

# Resource Limits
LimitNOFILE=1024
LimitNPROC=100
CPUQuota=50%
MemoryLimit=2G
TasksMax=50

# Sandboxing
ReadWritePaths=/opt/media-processor/queue /opt/media-processor/processed
ReadOnlyPaths=/opt/media-processor/bin

# seccomp
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallErrorNumber=EPERM

# Capabilities (drop all)
CapabilityBoundingSet=
AmbientCapabilities=

ExecStart=/opt/media-processor/bin/image_harden_cli --daemon --queue=/opt/media-processor/queue

[Install]
WantedBy=multi-user.target
```

### Install Instructions

```bash
# Create service user
sudo useradd -r -s /bin/false media-processor

# Create directories
sudo mkdir -p /opt/media-processor/{bin,queue,processed,quarantine}
sudo chown -R media-processor:media-processor /opt/media-processor

# Install binary
sudo cp image_harden/target/release/image_harden_cli /opt/media-processor/bin/
sudo chmod 755 /opt/media-processor/bin/image_harden_cli

# Install service
sudo cp hardened-media-processor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable hardened-media-processor
sudo systemctl start hardened-media-processor
```

## SELinux Policy (Optional)

```bash
# Generate initial policy
sudo ausearch -m avc -ts recent | audit2allow -M hardened-media-processor

# Review and refine
sudo semodule -i hardened-media-processor.pp
```

## AppArmor Profile (Alternative to SELinux)

```
#include <tunables/global>

/opt/media-processor/bin/image_harden_cli {
  #include <abstractions/base>

  # Allow reading from queue
  /opt/media-processor/queue/** r,

  # Allow writing to processed
  /opt/media-processor/processed/** rw,

  # Allow writing to quarantine
  /opt/media-processor/quarantine/** rw,

  # Deny everything else
  /** ix,

  # Libraries
  /usr/local/lib/libpng*.so* mr,
  /usr/local/lib/libjpeg*.so* mr,
  /usr/local/lib/libmpg123*.so* mr,
}
```

## Monitoring and Alerting

### Prometheus Metrics Exporter

```rust
// Add to image_harden/src/metrics.rs
use prometheus::{Counter, Histogram, Registry};

pub struct MediaMetrics {
    pub files_processed: Counter,
    pub files_rejected: Counter,
    pub processing_duration: Histogram,
    pub quarantined_files: Counter,
}

impl MediaMetrics {
    pub fn new(registry: &Registry) -> Self {
        let files_processed = Counter::new(
            "media_files_processed_total",
            "Total files processed successfully"
        ).unwrap();

        let files_rejected = Counter::new(
            "media_files_rejected_total",
            "Total files rejected (malformed/malicious)"
        ).unwrap();

        registry.register(Box::new(files_processed.clone())).unwrap();
        registry.register(Box::new(files_rejected.clone())).unwrap();

        Self {
            files_processed,
            files_rejected,
            processing_duration: Histogram::new(...).unwrap(),
            quarantined_files: Counter::new(...).unwrap(),
        }
    }
}
```

### Log Aggregation (Syslog)

```bash
# Configure rsyslog for security events
cat > /etc/rsyslog.d/50-media-hardening.conf <<'EOF'
# Media hardening security events
if $programname == 'media-processor' and $msg contains 'SECURITY' then {
    action(type="omfwd" target="siem.example.com" port="514" protocol="tcp")
    action(type="omfile" file="/var/log/media-security.log")
    stop
}
EOF

sudo systemctl restart rsyslog
```

## Automated Threat Intelligence Submission

```bash
#!/bin/bash
# submit_to_threat_intel.sh

QUARANTINE_DIR="/opt/media-processor/quarantine"
THREAT_INTEL_API="https://threat-intel.example.com/api/v1/submit"
API_KEY="your-api-key"

for file in "$QUARANTINE_DIR"/*.quarantined; do
    if [ -f "$file" ]; then
        # Calculate hashes
        SHA256=$(sha256sum "$file" | cut -d' ' -f1)
        MD5=$(md5sum "$file" | cut -d' ' -f1)

        # Submit to threat intel
        curl -X POST "$THREAT_INTEL_API" \
            -H "Authorization: Bearer $API_KEY" \
            -H "Content-Type: multipart/form-data" \
            -F "file=@$file" \
            -F "sha256=$SHA256" \
            -F "md5=$MD5" \
            -F "source=media-hardening" \
            -F "severity=high"

        # Log submission
        logger -t media-processor "Submitted $SHA256 to threat intel"
    fi
done
```

## CVE Monitoring and Auto-Patching

```bash
#!/bin/bash
# monitor_cves.sh - Check for CVEs in dependencies

echo "Checking for CVEs in Rust dependencies..."
cd image_harden
cargo audit || {
    echo "CRITICAL: CVEs found in dependencies!"
    # Send alert
    mail -s "SECURITY ALERT: CVEs in media-processor" admin@example.com <<< "Run cargo audit for details"
}

echo "Checking for CVEs in system packages..."
# For Debian
apt list --upgradable 2>/dev/null | grep -E "mpg123|libvorbis|libflac|libopus|ffmpeg" || true

echo "Checking NIST NVD for media codec CVEs..."
# Query NVD API for recent CVEs
curl "https://services.nvd.nist.gov/rest/json/cves/1.0?keyword=mp4+codec&resultsPerPage=5" | \
    jq '.result.CVE_Items[] | {id: .cve.CVE_data_meta.ID, description: .cve.description.description_data[0].value}'
```

## High Availability Setup

### Load Balancing Multiple Processors

```yaml
# docker-compose.yml for HA deployment
version: '3.8'
services:
  media-processor-1:
    image: media-processor:hardened
    cpus: '2'
    mem_limit: 2g
    security_opt:
      - no-new-privileges:true
      - seccomp=/path/to/seccomp.json
    volumes:
      - ./queue:/opt/media-processor/queue:ro
      - ./processed:/opt/media-processor/processed:rw
    networks:
      - processing-net

  media-processor-2:
    image: media-processor:hardened
    cpus: '2'
    mem_limit: 2g
    security_opt:
      - no-new-privileges:true
      - seccomp=/path/to/seccomp.json
    volumes:
      - ./queue:/opt/media-processor/queue:ro
      - ./processed:/opt/media-processor/processed:rw
    networks:
      - processing-net

  load-balancer:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - processing-net

networks:
  processing-net:
    driver: bridge
```

## Backup and Disaster Recovery

```bash
#!/bin/bash
# backup_configs.sh

BACKUP_DIR="/backup/media-hardening/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Backup kernel configs
cp -r /opt/hardened-audio-drivers "$BACKUP_DIR/"
cp -r /opt/hardened-drivers "$BACKUP_DIR/"

# Backup systemd services
cp /etc/systemd/system/hardened-media-processor.service "$BACKUP_DIR/"

# Backup application binaries
cp /opt/media-processor/bin/* "$BACKUP_DIR/"

# Create manifest
cat > "$BACKUP_DIR/manifest.txt" <<EOF
Backup Date: $(date)
Kernel Version: $(uname -r)
Xen Support: $([ -d /proc/xen ] && echo "YES" || echo "NO")
Binary Hash: $(sha256sum /opt/media-processor/bin/image_harden_cli | cut -d' ' -f1)
EOF

# Compress
tar czf "$BACKUP_DIR.tar.gz" -C /backup/media-hardening "$(basename $BACKUP_DIR)"

# Upload to S3 (optional)
# aws s3 cp "$BACKUP_DIR.tar.gz" s3://backups/media-hardening/
```

## Performance Tuning

### Kernel Parameters for Media Processing

```bash
# /etc/sysctl.d/99-media-hardening.conf

# Increase max open files for media processor
fs.file-max = 100000

# Increase network buffer sizes
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728

# Reduce swappiness (prefer RAM)
vm.swappiness = 10

# Increase DMA buffer limits (if needed)
# vm.max_map_count = 262144

# Xen-specific tuning (if on Xen)
# xen.balloon.min_free_kbytes = 131072
```

Apply with: `sudo sysctl -p /etc/sysctl.d/99-media-hardening.conf`

## Security Event Response Playbook

### Incident Response Steps

1. **Detection**: Quarantine file triggers alert
   ```bash
   # Automatic alert via systemd OnFailure
   sudo journalctl -u hardened-media-processor -f | grep SECURITY
   ```

2. **Containment**: Stop processing queue
   ```bash
   sudo systemctl stop hardened-media-processor
   ```

3. **Analysis**: Extract IOCs from quarantined file
   ```bash
   cd /opt/media-processor/quarantine
   file suspicious.mp4.quarantined
   exiftool suspicious.mp4.quarantined
   strings suspicious.mp4.quarantined | grep -E "http|powershell|cmd"
   ```

4. **Eradication**: Remove threat and update signatures
   ```bash
   # Update ClamAV signatures (if using)
   sudo freshclam
   # Re-scan quarantine
   clamscan /opt/media-processor/quarantine/
   ```

5. **Recovery**: Resume processing
   ```bash
   sudo systemctl start hardened-media-processor
   ```

6. **Lessons Learned**: Update documentation
   ```bash
   echo "$(date): Incident XYZ - Updated parser for new exploit variant" >> /var/log/incidents.log
   ```

## Compliance and Auditing

### Generate Compliance Report

```bash
#!/bin/bash
# compliance_report.sh

cat > /tmp/compliance_report.txt <<EOF
MEDIA HARDENING COMPLIANCE REPORT
Generated: $(date)

=== Configuration Status ===
EOF

# Check hardening flags
echo "Kernel Hardening:" >> /tmp/compliance_report.txt
grep -E "CONFIG_FORTIFY_SOURCE|CONFIG_STACKPROTECTOR|CONFIG_HARDENED" /boot/config-$(uname -r) >> /tmp/compliance_report.txt || echo "  [WARN] Hardening config not found" >> /tmp/compliance_report.txt

# Check seccomp
echo -e "\nSeccomp Status:" >> /tmp/compliance_report.txt
grep Seccomp /proc/self/status >> /tmp/compliance_report.txt

# Check loaded modules
echo -e "\nLoaded Media Modules:" >> /tmp/compliance_report.txt
lsmod | grep -E "snd|video|drm" >> /tmp/compliance_report.txt

# Check service status
echo -e "\nService Status:" >> /tmp/compliance_report.txt
systemctl is-active hardened-media-processor >> /tmp/compliance_report.txt

# Check Xen
echo -e "\nXen Status:" >> /tmp/compliance_report.txt
[ -d /proc/xen ] && cat /proc/xen/capabilities >> /tmp/compliance_report.txt || echo "  Not on Xen" >> /tmp/compliance_report.txt

# Summary
echo -e "\n=== Summary ===" >> /tmp/compliance_report.txt
echo "Status: $([ -f /opt/hardened-drivers/configs/kernel-hardened-media.config ] && echo 'COMPLIANT' || echo 'NON-COMPLIANT')" >> /tmp/compliance_report.txt

cat /tmp/compliance_report.txt
```

## Zero-Trust Architecture Integration

```bash
# /opt/media-processor/policy/zero-trust.yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: media-processor-policy
spec:
  selector:
    matchLabels:
      app: media-processor
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/upload-service"]
    to:
    - operation:
        methods: ["POST"]
        paths: ["/api/v1/process"]
```

## Automated Testing in Production

```bash
#!/bin/bash
# canary_test.sh - Continuous validation with known-good samples

CANARY_DIR="/opt/media-processor/canary-samples"
RESULTS_LOG="/var/log/canary-test.log"

for sample in "$CANARY_DIR"/*.{png,mp3,mp4}; do
    if [ -f "$sample" ]; then
        echo "[$(date)] Testing: $sample" >> "$RESULTS_LOG"

        timeout 30s /opt/media-processor/bin/image_harden_cli "$sample" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "  [PASS] $sample" >> "$RESULTS_LOG"
        else
            echo "  [FAIL] $sample - ALERT!" >> "$RESULTS_LOG"
            # Send alert
            mail -s "ALERT: Canary test failed" admin@example.com <<< "Sample: $sample failed validation"
        fi
    fi
done
```

---

## Quick Start for Production

```bash
# 1. Install as systemd service
sudo ./install_production.sh

# 2. Configure monitoring
sudo ./setup_monitoring.sh

# 3. Run compliance check
sudo ./compliance_report.sh

# 4. Start canary testing
sudo systemctl enable --now canary-test.timer

# 5. Verify
sudo systemctl status hardened-media-processor
sudo journalctl -u hardened-media-processor -f
```

Ready for enterprise deployment! 🚀

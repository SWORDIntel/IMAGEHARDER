// Prometheus Metrics for Media Hardening
// Tracks processing statistics, security events, and performance

use lazy_static::lazy_static;
use prometheus::{
    Counter, CounterVec, Gauge, GaugeVec, Histogram, HistogramVec, Opts, Registry,
};
use std::sync::Arc;

lazy_static! {
    pub static ref REGISTRY: Registry = Registry::new();

    // Files processed counters
    pub static ref FILES_PROCESSED_TOTAL: CounterVec = CounterVec::new(
        Opts::new("media_processor_files_processed_total", "Total number of files processed")
            .namespace("media_hardening"),
        &["format", "status"]
    ).unwrap();

    pub static ref FILES_FAILED_TOTAL: CounterVec = CounterVec::new(
        Opts::new("media_processor_files_failed_total", "Total number of files that failed processing")
            .namespace("media_hardening"),
        &["format", "error_type"]
    ).unwrap();

    // Security metrics
    pub static ref SECURITY_VIOLATIONS_TOTAL: CounterVec = CounterVec::new(
        Opts::new("media_processor_security_violations_total", "Total security violations detected")
            .namespace("media_hardening"),
        &["violation_type", "format"]
    ).unwrap();

    pub static ref MALWARE_DETECTED_TOTAL: Counter = Counter::new(
        "media_hardening_media_processor_malware_detected_total",
        "Total malware detections"
    ).unwrap();

    pub static ref FILES_QUARANTINED_TOTAL: Counter = Counter::new(
        "media_hardening_media_processor_files_quarantined_total",
        "Total files quarantined"
    ).unwrap();

    pub static ref BUFFER_OVERFLOW_ATTEMPTS_TOTAL: Counter = Counter::new(
        "media_hardening_media_processor_buffer_overflow_attempts_total",
        "Total buffer overflow attempts detected"
    ).unwrap();

    pub static ref RESOURCE_LIMIT_VIOLATIONS_TOTAL: CounterVec = CounterVec::new(
        Opts::new("media_processor_resource_limit_violations_total", "Resource limit violations")
            .namespace("media_hardening"),
        &["limit_type"]
    ).unwrap();

    // Processing performance metrics
    pub static ref PROCESSING_DURATION_SECONDS: HistogramVec = HistogramVec::new(
        prometheus::HistogramOpts::new(
            "media_processor_processing_duration_seconds",
            "Processing duration in seconds"
        )
        .namespace("media_hardening")
        .buckets(vec![0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0]),
        &["format"]
    ).unwrap();

    pub static ref FILE_SIZE_BYTES: HistogramVec = HistogramVec::new(
        prometheus::HistogramOpts::new(
            "media_processor_file_size_bytes",
            "File size distribution in bytes"
        )
        .namespace("media_hardening")
        .buckets(vec![1024.0, 10240.0, 102400.0, 1048576.0, 10485760.0, 104857600.0]),
        &["format"]
    ).unwrap();

    // Memory and CPU metrics
    pub static ref MEMORY_BYTES: Gauge = Gauge::new(
        "media_hardening_media_processor_memory_bytes",
        "Current memory usage in bytes"
    ).unwrap();

    pub static ref MEMORY_LIMIT_BYTES: Gauge = Gauge::new(
        "media_hardening_media_processor_memory_limit_bytes",
        "Memory limit in bytes"
    ).unwrap();

    pub static ref CPU_SECONDS_TOTAL: Counter = Counter::new(
        "media_hardening_media_processor_cpu_seconds_total",
        "Total CPU time used"
    ).unwrap();

    // Validation metrics
    pub static ref MALFORMED_FILES_TOTAL: CounterVec = CounterVec::new(
        Opts::new("media_processor_malformed_files_total", "Total malformed files detected")
            .namespace("media_hardening"),
        &["format"]
    ).unwrap();

    pub static ref VALIDATION_FAILURES_TOTAL: CounterVec = CounterVec::new(
        Opts::new("media_processor_validation_failures_total", "Validation check failures")
            .namespace("media_hardening"),
        &["check_type"]
    ).unwrap();

    pub static ref SUSPICIOUS_PATTERNS_TOTAL: CounterVec = CounterVec::new(
        Opts::new("media_processor_suspicious_patterns_total", "Suspicious patterns detected")
            .namespace("media_hardening"),
        &["pattern", "format"]
    ).unwrap();

    // System security metrics
    pub static ref SECCOMP_VIOLATIONS_TOTAL: Counter = Counter::new(
        "media_hardening_media_processor_seccomp_violations_total",
        "Seccomp syscall violations"
    ).unwrap();

    pub static ref MEMORY_VIOLATIONS_TOTAL: CounterVec = CounterVec::new(
        Opts::new("media_processor_memory_violations_total", "Memory safety violations")
            .namespace("media_hardening"),
        &["type"]
    ).unwrap();

    pub static ref ERRORS_TOTAL: CounterVec = CounterVec::new(
        Opts::new("media_processor_errors_total", "Total errors by type")
            .namespace("media_hardening"),
        &["error_type"]
    ).unwrap();

    // CVE and security audit metrics
    pub static ref KNOWN_CVES: Gauge = Gauge::new(
        "media_hardening_media_processor_known_cves",
        "Number of known CVEs in dependencies"
    ).unwrap();

    pub static ref LAST_SECURITY_AUDIT_TIMESTAMP: Gauge = Gauge::new(
        "media_hardening_media_processor_last_security_audit_timestamp",
        "Unix timestamp of last security audit"
    ).unwrap();
}

/// Initialize and register all metrics with the Prometheus registry
pub fn init_metrics() -> Result<(), Box<dyn std::error::Error>> {
    REGISTRY.register(Box::new(FILES_PROCESSED_TOTAL.clone()))?;
    REGISTRY.register(Box::new(FILES_FAILED_TOTAL.clone()))?;
    REGISTRY.register(Box::new(SECURITY_VIOLATIONS_TOTAL.clone()))?;
    REGISTRY.register(Box::new(MALWARE_DETECTED_TOTAL.clone()))?;
    REGISTRY.register(Box::new(FILES_QUARANTINED_TOTAL.clone()))?;
    REGISTRY.register(Box::new(BUFFER_OVERFLOW_ATTEMPTS_TOTAL.clone()))?;
    REGISTRY.register(Box::new(RESOURCE_LIMIT_VIOLATIONS_TOTAL.clone()))?;
    REGISTRY.register(Box::new(PROCESSING_DURATION_SECONDS.clone()))?;
    REGISTRY.register(Box::new(FILE_SIZE_BYTES.clone()))?;
    REGISTRY.register(Box::new(MEMORY_BYTES.clone()))?;
    REGISTRY.register(Box::new(MEMORY_LIMIT_BYTES.clone()))?;
    REGISTRY.register(Box::new(CPU_SECONDS_TOTAL.clone()))?;
    REGISTRY.register(Box::new(MALFORMED_FILES_TOTAL.clone()))?;
    REGISTRY.register(Box::new(VALIDATION_FAILURES_TOTAL.clone()))?;
    REGISTRY.register(Box::new(SUSPICIOUS_PATTERNS_TOTAL.clone()))?;
    REGISTRY.register(Box::new(SECCOMP_VIOLATIONS_TOTAL.clone()))?;
    REGISTRY.register(Box::new(MEMORY_VIOLATIONS_TOTAL.clone()))?;
    REGISTRY.register(Box::new(ERRORS_TOTAL.clone()))?;
    REGISTRY.register(Box::new(KNOWN_CVES.clone()))?;
    REGISTRY.register(Box::new(LAST_SECURITY_AUDIT_TIMESTAMP.clone()))?;

    // Set initial values
    MEMORY_LIMIT_BYTES.set(2_000_000_000.0); // 2GB default
    KNOWN_CVES.set(0.0);
    LAST_SECURITY_AUDIT_TIMESTAMP.set(std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs() as f64);

    Ok(())
}

/// Record a successful file processing
pub fn record_file_processed(format: &str, file_size: usize, duration_secs: f64) {
    FILES_PROCESSED_TOTAL
        .with_label_values(&[format, "success"])
        .inc();
    FILE_SIZE_BYTES
        .with_label_values(&[format])
        .observe(file_size as f64);
    PROCESSING_DURATION_SECONDS
        .with_label_values(&[format])
        .observe(duration_secs);
}

/// Record a failed file processing
pub fn record_file_failed(format: &str, error_type: &str) {
    FILES_FAILED_TOTAL
        .with_label_values(&[format, error_type])
        .inc();
    ERRORS_TOTAL
        .with_label_values(&[error_type])
        .inc();
}

/// Record a security violation
pub fn record_security_violation(violation_type: &str, format: &str) {
    SECURITY_VIOLATIONS_TOTAL
        .with_label_values(&[violation_type, format])
        .inc();
}

/// Record a malformed file detection
pub fn record_malformed_file(format: &str) {
    MALFORMED_FILES_TOTAL
        .with_label_values(&[format])
        .inc();
}

/// Update memory usage gauge
pub fn update_memory_usage(bytes: usize) {
    MEMORY_BYTES.set(bytes as f64);
}

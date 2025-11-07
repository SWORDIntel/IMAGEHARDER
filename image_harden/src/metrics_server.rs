// Prometheus Metrics HTTP Server
// Serves metrics on /metrics endpoint for Prometheus scraping

use crate::metrics::REGISTRY;
use prometheus::{Encoder, TextEncoder};
use std::io::Write;
use std::thread;
use tiny_http::{Response, Server};

/// Start the metrics HTTP server on the specified port
/// This runs in a separate thread to avoid blocking the main processing
pub fn start_metrics_server(port: u16) -> Result<(), Box<dyn std::error::Error>> {
    let addr = format!("0.0.0.0:{}", port);
    let server = Server::http(&addr)?;

    println!("Metrics server listening on http://{}/metrics", addr);

    thread::spawn(move || {
        for request in server.incoming_requests() {
            let response = match request.url() {
                "/metrics" => {
                    // Gather metrics and encode in Prometheus format
                    let encoder = TextEncoder::new();
                    let metric_families = REGISTRY.gather();
                    let mut buffer = Vec::new();

                    if let Err(e) = encoder.encode(&metric_families, &mut buffer) {
                        eprintln!("Failed to encode metrics: {}", e);
                        Response::from_string("Failed to encode metrics")
                            .with_status_code(500)
                    } else {
                        Response::from_data(buffer)
                            .with_header(
                                tiny_http::Header::from_bytes(&b"Content-Type"[..],
                                &b"text/plain; version=0.0.4"[..]).unwrap()
                            )
                    }
                }
                "/health" => {
                    // Basic health check endpoint
                    Response::from_string("OK")
                }
                "/" => {
                    // Root endpoint - provide basic info
                    let info = r#"
Media Hardening Metrics Server

Available endpoints:
  /metrics - Prometheus metrics (text format)
  /health  - Health check

For Prometheus configuration, add this scrape config:
  - job_name: 'media-processor'
    static_configs:
      - targets: ['<host>:8080']
"#;
                    Response::from_string(info)
                }
                _ => {
                    Response::from_string("Not Found").with_status_code(404)
                }
            };

            if let Err(e) = request.respond(response) {
                eprintln!("Failed to send response: {}", e);
            }
        }
    });

    Ok(())
}

/// Start metrics server with default port (8080)
pub fn start_default_metrics_server() -> Result<(), Box<dyn std::error::Error>> {
    start_metrics_server(8080)
}

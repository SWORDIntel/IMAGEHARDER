# Multi-stage Hardened Docker Build
# Produces minimal, secure container for media processing

# Stage 1: Builder
FROM debian:bookworm-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    cmake \
    nasm \
    autoconf \
    automake \
    libtool \
    git \
    pkg-config \
    libseccomp-dev \
    librsvg2-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Copy source
WORKDIR /build
COPY . .

# Initialize submodules
RUN git submodule update --init --recursive || true

# Build hardened libraries
RUN ./build.sh && ./build_audio.sh

# Build Rust application
WORKDIR /build/image_harden
RUN cargo build --release

# Stage 2: Runtime (Minimal)
FROM debian:bookworm-slim

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    libseccomp2 \
    librsvg2-2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -r -u 1000 -s /bin/false media-processor

# Copy built artifacts
COPY --from=builder /build/image_harden/target/release/image_harden_cli /usr/local/bin/
COPY --from=builder /usr/local/lib/libpng*.a /usr/local/lib/
COPY --from=builder /usr/local/lib/libjpeg*.a /usr/local/lib/
COPY --from=builder /usr/local/lib/libmpg123*.a /usr/local/lib/
COPY --from=builder /usr/local/lib/libvorbis*.a /usr/local/lib/
COPY --from=builder /usr/local/lib/libflac*.a /usr/local/lib/

# Create directories
RUN mkdir -p /data/input /data/output /data/quarantine && \
    chown -R media-processor:media-processor /data

# Security hardening
USER media-processor
WORKDIR /data

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /usr/local/bin/image_harden_cli --version || exit 1

# Metadata
LABEL maintainer="security@example.com" \
      description="Hardened Media Processing Container" \
      version="1.0" \
      security.capabilities="drop-all"

ENTRYPOINT ["/usr/local/bin/image_harden_cli"]
CMD ["--help"]

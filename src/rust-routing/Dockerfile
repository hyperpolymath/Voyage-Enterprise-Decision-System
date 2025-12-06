# VEDS Route Optimizer - Dockerfile
# Multi-stage build for minimal production image

# Build stage
FROM rust:1.75-bookworm as builder

WORKDIR /app

# Install protobuf compiler
RUN apt-get update && apt-get install -y protobuf-compiler && rm -rf /var/lib/apt/lists/*

# Copy manifests
COPY Cargo.toml Cargo.lock ./

# Create dummy src to cache dependencies
RUN mkdir -p src proto && \
    echo "fn main() {}" > src/main.rs && \
    echo 'syntax = "proto3"; package dummy;' > proto/optimizer.proto

# Build dependencies (cached)
RUN cargo build --release && rm -rf src proto

# Copy actual source
COPY . .

# Touch main.rs to force rebuild
RUN touch src/main.rs

# Build release binary
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=builder /app/target/release/veds-optimizer /app/veds-optimizer

# Create non-root user
RUN useradd -r -s /bin/false veds
USER veds

# Expose ports
EXPOSE 50051 8090

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD curl -f http://localhost:8090/health || exit 1

# Run
CMD ["/app/veds-optimizer"]

# VEDS Constraint Engine - Dockerfile
# Multi-stage build for Clojure

# Build stage
FROM clojure:temurin-21-tools-deps-alpine AS builder

WORKDIR /app

# Copy dependency files
COPY deps.edn ./

# Download dependencies
RUN clojure -P

# Copy source
COPY src src
COPY resources resources

# Build uberjar
RUN clojure -T:build uber

# Runtime stage
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# Create non-root user
RUN addgroup -g 1000 veds && \
    adduser -u 1000 -G veds -s /bin/sh -D veds

# Copy jar from builder
COPY --from=builder /app/target/veds-constraints.jar ./veds-constraints.jar

# Set ownership
RUN chown -R veds:veds /app

USER veds

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run
CMD ["java", "-jar", "veds-constraints.jar"]

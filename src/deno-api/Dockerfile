# SPDX-License-Identifier: MIT OR AGPL-3.0
# VEDS API - Deno Container

FROM denoland/deno:2.1.4

WORKDIR /app

# Copy configuration files
COPY deno.json ./
COPY rescript.json ./

# Copy source
COPY src/ ./src/

# Cache dependencies
RUN deno cache src/main.ts

# Run as non-root user
USER deno

# Expose port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4000/health || exit 1

# Start server
CMD ["run", "--allow-net", "--allow-env", "--allow-read", "src/main.ts"]

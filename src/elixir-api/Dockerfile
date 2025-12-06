# VEDS API - Dockerfile
# Multi-stage build for Elixir/Phoenix

# Build stage
FROM elixir:1.16-otp-26-alpine AS builder

RUN apk add --no-cache build-base git npm

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build environment
ENV MIX_ENV=prod

# Copy dependency files
COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/

# Install dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy assets
COPY assets assets
COPY priv priv

# Build assets
RUN npm install --prefix assets
RUN mix assets.deploy

# Copy application code
COPY lib lib

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM alpine:3.19 AS runtime

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

# Create non-root user
RUN addgroup -g 1000 veds && \
    adduser -u 1000 -G veds -s /bin/sh -D veds

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/veds ./

# Set ownership
RUN chown -R veds:veds /app

USER veds

# Expose port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
    CMD wget --no-verbose --tries=1 --spider http://localhost:4000/api/v1/health || exit 1

# Start command
CMD ["bin/veds", "start"]

# Voyage-Enterprise-Decision-System - Development Tasks
set shell := ["bash", "-uc"]
set dotenv-load := true

project := "Voyage-Enterprise-Decision-System"

# Show all recipes
default:
    @just --list --unsorted

# Build all components
build: build-rust build-deno build-julia

# Build Rust optimizer
build-rust:
    cd src/rust-routing && cargo build --release

# Build Deno API (compile ReScript)
build-deno:
    cd src/deno-api && deno cache src/main.ts

# Build Julia packages
build-julia:
    cd src/julia-viz && julia --project=. -e 'using Pkg; Pkg.instantiate()'
    cd test && julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Run all tests (property tests only by default)
test:
    julia --project=test test/runtests.jl

# Run integration tests (requires running containers)
test-integration:
    VEDS_TEST_INTEGRATION=true julia --project=test test/runtests.jl

# Run property-based tests
test-property:
    VEDS_TEST_PROPERTY=true julia --project=test test/runtests.jl

# Seed databases with synthetic data
seed:
    julia --project=src/julia-viz scripts/seed_data.jl

# Seed with custom URLs
seed-custom surrealdb_url dragonfly_url:
    julia --project=src/julia-viz scripts/seed_data.jl --surrealdb-url {{surrealdb_url}} --dragonfly-url {{dragonfly_url}}

# Start Docker containers for development
containers-up:
    docker-compose up -d

# Stop Docker containers
containers-down:
    docker-compose down

# Clean build artifacts
clean:
    find . -name "*.cov" -delete
    find . -name "*.mem" -delete
    rm -rf test/Manifest.toml
    rm -rf src/julia-viz/Manifest.toml

# Format Julia code
fmt:
    julia --project=src/julia-viz -e 'using JuliaFormatter; format("src"); format("test"); format("scripts")'

# Lint Julia code
lint:
    julia --project=src/julia-viz -e 'using StaticLint; lint("src/julia-viz/src")'

# Start visualization server
serve:
    julia --project=src/julia-viz -e 'using VEDSViz; app = VEDSApp(); start_server(app)'

# Start Deno API server
serve-api:
    cd src/deno-api && deno run --allow-net --allow-env --allow-read src/main.ts

# Start Deno API in watch mode
serve-api-dev:
    cd src/deno-api && deno run --allow-net --allow-env --allow-read --watch src/main.ts

# Start Rust optimizer
serve-optimizer:
    cd src/rust-routing && cargo run --release

# Initialize databases with schemas
db-init:
    @echo "Initializing SurrealDB schema..."
    curl -X POST -H "Accept: application/json" -H "NS: veds" -H "DB: production" \
        -u "root:veds_dev_password" \
        --data-binary @db/schemas/surrealdb.surql \
        http://localhost:8000/sql
    @echo "Database initialized."

# Seed databases with sample data
db-seed:
    @echo "Seeding SurrealDB with transport network..."
    curl -X POST -H "Accept: application/json" -H "NS: veds" -H "DB: production" \
        -u "root:veds_dev_password" \
        --data-binary @db/seeds/transport_network.surql \
        http://localhost:8000/sql
    @echo "Database seeded."

# Reset and reinitialize databases
db-reset: containers-down containers-up
    @sleep 5
    just db-init
    just db-seed

# Run all services (for development)
dev: containers-up
    @echo "Starting development services..."
    @echo "Waiting for databases..."
    @sleep 10
    just db-init
    just db-seed
    @echo "Starting API server..."
    just serve-api-dev

# Check service health
health:
    @echo "=== Service Health ==="
    @echo "SurrealDB:" && curl -s http://localhost:8000/health || echo "DOWN"
    @echo "XTDB:" && curl -s http://localhost:3000/status || echo "DOWN"
    @echo "Dragonfly:" && redis-cli -a veds_dev_password ping || echo "DOWN"
    @echo "API:" && curl -s http://localhost:4000/health || echo "DOWN"
    @echo "Optimizer:" && curl -s http://localhost:8090/health || echo "DOWN"

# Run Rust tests
test-rust:
    cd src/rust-routing && cargo test

# Run all component tests
test-all: test test-rust

# Generate API client from protobuf
proto-gen:
    cd src/rust-routing && cargo build

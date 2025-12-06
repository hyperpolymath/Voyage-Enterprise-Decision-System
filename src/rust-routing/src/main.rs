//! VEDS Route Optimizer
//!
//! High-performance multimodal transport route optimization engine.
//! Finds optimal paths across maritime, rail, road, and air networks.

mod graph;
mod optimizer;
mod constraints;
mod grpc;
mod db;

use anyhow::Result;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, Level};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

use crate::graph::TransportGraph;
use crate::grpc::OptimizerServer;

/// Application configuration
#[derive(Debug, Clone)]
pub struct Config {
    pub grpc_port: u16,
    pub metrics_port: u16,
    pub surrealdb_url: String,
    pub surrealdb_user: String,
    pub surrealdb_pass: String,
    pub dragonfly_url: String,
    pub dragonfly_pass: Option<String>,
    pub graph_reload_interval_secs: u64,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        dotenvy::dotenv().ok();

        Ok(Config {
            grpc_port: std::env::var("GRPC_PORT")
                .unwrap_or_else(|_| "50051".to_string())
                .parse()?,
            metrics_port: std::env::var("METRICS_PORT")
                .unwrap_or_else(|_| "8090".to_string())
                .parse()?,
            surrealdb_url: std::env::var("SURREALDB_URL")
                .unwrap_or_else(|_| "ws://localhost:8000".to_string()),
            surrealdb_user: std::env::var("SURREALDB_USER")
                .unwrap_or_else(|_| "root".to_string()),
            surrealdb_pass: std::env::var("SURREALDB_PASS")
                .unwrap_or_else(|_| "veds_dev_password".to_string()),
            dragonfly_url: std::env::var("DRAGONFLY_URL")
                .unwrap_or_else(|_| "redis://localhost:6379".to_string()),
            dragonfly_pass: std::env::var("DRAGONFLY_PASS").ok(),
            graph_reload_interval_secs: std::env::var("GRAPH_RELOAD_INTERVAL")
                .unwrap_or_else(|_| "300".to_string())
                .parse()?,
        })
    }
}

/// Shared application state
pub struct AppState {
    pub config: Config,
    pub graph: RwLock<TransportGraph>,
    pub redis: redis::aio::ConnectionManager,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::registry()
        .with(fmt::layer().with_target(true))
        .with(
            EnvFilter::builder()
                .with_default_directive(Level::INFO.into())
                .from_env_lossy(),
        )
        .init();

    info!("Starting VEDS Route Optimizer");

    // Load configuration
    let config = Config::from_env()?;
    info!(?config, "Configuration loaded");

    // Connect to Dragonfly/Redis
    let redis_url = if let Some(ref pass) = config.dragonfly_pass {
        format!(
            "redis://:{}@{}",
            pass,
            config.dragonfly_url.trim_start_matches("redis://")
        )
    } else {
        config.dragonfly_url.clone()
    };
    let redis_client = redis::Client::open(redis_url)?;
    let redis_conn = redis::aio::ConnectionManager::new(redis_client).await?;
    info!("Connected to Dragonfly/Redis");

    // Initialize transport graph
    let graph = TransportGraph::new();
    info!("Transport graph initialized (empty)");

    // Create shared state
    let state = Arc::new(AppState {
        config: config.clone(),
        graph: RwLock::new(graph),
        redis: redis_conn,
    });

    // Load initial graph from database
    {
        let mut graph = state.graph.write().await;
        match db::load_graph_from_surrealdb(&config).await {
            Ok(loaded_graph) => {
                *graph = loaded_graph;
                info!(
                    nodes = graph.node_count(),
                    edges = graph.edge_count(),
                    "Transport graph loaded from SurrealDB"
                );
            }
            Err(e) => {
                tracing::warn!("Failed to load graph from SurrealDB: {}. Starting with empty graph.", e);
            }
        }
    }

    // Spawn background graph reload task
    let state_clone = Arc::clone(&state);
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(
            std::time::Duration::from_secs(state_clone.config.graph_reload_interval_secs)
        );
        loop {
            interval.tick().await;
            if let Ok(new_graph) = db::load_graph_from_surrealdb(&state_clone.config).await {
                let mut graph = state_clone.graph.write().await;
                *graph = new_graph;
                info!("Transport graph reloaded");
            }
        }
    });

    // Spawn metrics server
    let metrics_port = config.metrics_port;
    tokio::spawn(async move {
        let app = axum::Router::new()
            .route("/metrics", axum::routing::get(metrics_handler))
            .route("/health", axum::routing::get(health_handler));

        let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", metrics_port))
            .await
            .unwrap();
        info!("Metrics server listening on port {}", metrics_port);
        axum::serve(listener, app).await.unwrap();
    });

    // Start gRPC server
    let addr = format!("0.0.0.0:{}", config.grpc_port).parse()?;
    info!("gRPC server listening on {}", addr);

    tonic::transport::Server::builder()
        .add_service(grpc::optimizer_service_server(state))
        .serve(addr)
        .await?;

    Ok(())
}

async fn metrics_handler() -> String {
    use prometheus::Encoder;
    let encoder = prometheus::TextEncoder::new();
    let metric_families = prometheus::gather();
    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer).unwrap();
    String::from_utf8(buffer).unwrap()
}

async fn health_handler() -> &'static str {
    "OK"
}

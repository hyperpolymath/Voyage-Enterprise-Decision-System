//! Database Connectivity
//!
//! Connects to SurrealDB for transport graph data.

use crate::graph::{TransportGraph, TransportNode, TransportEdge, TransportMode};
use crate::Config;
use anyhow::{Result, Context};
use rust_decimal::Decimal;
use serde::Deserialize;
use surrealdb::engine::remote::ws::{Client, Ws};
use surrealdb::opt::auth::Root;
use surrealdb::Surreal;
use tracing::info;

/// Raw node data from SurrealDB
#[derive(Debug, Deserialize)]
struct RawNode {
    id: surrealdb::sql::Thing,
    code: String,
    port: RawPort,
    node_type: String,
    modes: Vec<String>,
    active: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct RawPort {
    unlocode: String,
    name: String,
    country: RawCountry,
    location: Option<RawLocation>,
    timezone: Option<String>,
    avg_dwell_hours: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct RawCountry {
    code: String,
}

#[derive(Debug, Deserialize)]
struct RawLocation {
    coordinates: (f64, f64),  // [lon, lat]
}

/// Raw edge data from SurrealDB
#[derive(Debug, Deserialize)]
struct RawEdge {
    id: surrealdb::sql::Thing,
    code: String,
    from_node: RawNodeRef,
    to_node: RawNodeRef,
    carrier: RawCarrier,
    mode: String,
    distance_km: f64,
    base_cost_usd: f64,
    cost_per_kg_usd: Option<f64>,
    transit_hours: f64,
    carbon_kg_per_tonne_km: f64,
    active: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct RawNodeRef {
    code: String,
}

#[derive(Debug, Deserialize)]
struct RawCarrier {
    code: String,
    name: String,
    avg_wage_cents_hourly: Option<i32>,
    safety_rating: Option<i32>,
    unionized: Option<bool>,
    sanctioned: Option<bool>,
}

/// Load the transport graph from SurrealDB
pub async fn load_graph_from_surrealdb(config: &Config) -> Result<TransportGraph> {
    let start = std::time::Instant::now();

    // Connect to SurrealDB
    let db = Surreal::new::<Ws>(&config.surrealdb_url)
        .await
        .context("Failed to connect to SurrealDB")?;

    // Sign in
    db.signin(Root {
        username: &config.surrealdb_user,
        password: &config.surrealdb_pass,
    })
    .await
    .context("Failed to authenticate with SurrealDB")?;

    // Select namespace and database
    db.use_ns("veds").use_db("production").await?;

    let mut graph = TransportGraph::new();

    // Load nodes
    let nodes: Vec<RawNode> = db
        .query("SELECT * FROM transport_node WHERE active = true FETCH port, port.country")
        .await?
        .take(0)?;

    info!(count = nodes.len(), "Loaded nodes from SurrealDB");

    for raw_node in nodes {
        let modes: Vec<TransportMode> = raw_node
            .modes
            .iter()
            .filter_map(|m| parse_mode(m))
            .collect();

        let (lon, lat) = raw_node
            .port
            .location
            .map(|l| l.coordinates)
            .unwrap_or((0.0, 0.0));

        let node = TransportNode {
            id: raw_node.id.to_string(),
            code: raw_node.code,
            name: raw_node.port.name,
            country_code: raw_node.port.country.code,
            lat,
            lon,
            modes,
            avg_dwell_hours: raw_node.port.avg_dwell_hours.unwrap_or(24.0),
        };

        graph.add_node(node);
    }

    // Load edges
    let edges: Vec<RawEdge> = db
        .query("SELECT * FROM transport_edge WHERE active = true FETCH from_node, to_node, carrier")
        .await?
        .take(0)?;

    info!(count = edges.len(), "Loaded edges from SurrealDB");

    for raw_edge in edges {
        let Some(mode) = parse_mode(&raw_edge.mode) else {
            continue;
        };

        let edge = TransportEdge {
            id: raw_edge.id.to_string(),
            code: raw_edge.code,
            mode,
            carrier_code: raw_edge.carrier.code,
            carrier_name: raw_edge.carrier.name,
            distance_km: raw_edge.distance_km,
            base_cost_usd: Decimal::from_f64_retain(raw_edge.base_cost_usd)
                .unwrap_or(Decimal::ZERO),
            cost_per_kg: Decimal::from_f64_retain(raw_edge.cost_per_kg_usd.unwrap_or(0.0))
                .unwrap_or(Decimal::ZERO),
            transit_hours: raw_edge.transit_hours,
            carbon_per_tonne_km: raw_edge.carbon_kg_per_tonne_km,
            carrier_wage_cents: raw_edge.carrier.avg_wage_cents_hourly.unwrap_or(1500),
            carrier_safety_rating: raw_edge.carrier.safety_rating.unwrap_or(3),
            carrier_unionized: raw_edge.carrier.unionized.unwrap_or(false),
            carrier_sanctioned: raw_edge.carrier.sanctioned.unwrap_or(false),
            active: raw_edge.active.unwrap_or(true),
        };

        graph.add_edge(&raw_edge.from_node.code, &raw_edge.to_node.code, edge);
    }

    graph.load_time_ms = start.elapsed().as_millis() as u64;
    graph.loaded_at = chrono::Utc::now();

    Ok(graph)
}

fn parse_mode(s: &str) -> Option<TransportMode> {
    match s.to_uppercase().as_str() {
        "MARITIME" => Some(TransportMode::Maritime),
        "RAIL" => Some(TransportMode::Rail),
        "ROAD" => Some(TransportMode::Road),
        "AIR" => Some(TransportMode::Air),
        _ => None,
    }
}

/// Load constraint cache from Dragonfly
pub async fn load_constraints_from_dragonfly(
    redis: &mut redis::aio::ConnectionManager,
) -> Result<crate::constraints::ConstraintCache> {
    use redis::AsyncCommands;

    let mut cache = crate::constraints::ConstraintCache::default();

    // Load minimum wages
    let wage_keys: Vec<String> = redis
        .keys("constraint:min_wage:*")
        .await
        .unwrap_or_default();

    for key in wage_keys {
        if let Some(country) = key.strip_prefix("constraint:min_wage:") {
            if let Ok(wage) = redis.get::<_, i32>(&key).await {
                cache.min_wages.insert(country.to_string(), wage);
            }
        }
    }

    // Load sanctioned carriers
    let sanctioned: Vec<String> = redis
        .smembers("constraint:sanctioned:carriers")
        .await
        .unwrap_or_default();

    cache.sanctioned_carriers = sanctioned.into_iter().collect();

    Ok(cache)
}

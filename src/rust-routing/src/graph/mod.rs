//! Transport Network Graph
//!
//! In-memory graph representation of the multimodal transport network.
//! Optimized for fast path-finding operations.

use petgraph::graph::{DiGraph, NodeIndex};
use petgraph::algo::dijkstra;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use chrono::{DateTime, Utc};

/// Transport mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum TransportMode {
    Maritime,
    Rail,
    Road,
    Air,
}

impl std::fmt::Display for TransportMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TransportMode::Maritime => write!(f, "MARITIME"),
            TransportMode::Rail => write!(f, "RAIL"),
            TransportMode::Road => write!(f, "ROAD"),
            TransportMode::Air => write!(f, "AIR"),
        }
    }
}

impl TransportMode {
    /// Default carbon emission factor (kg CO2 per tonne-km)
    pub fn default_carbon_factor(&self) -> f64 {
        match self {
            TransportMode::Maritime => 0.020,  // Container ship average
            TransportMode::Rail => 0.025,      // Diesel rail average
            TransportMode::Road => 0.100,      // Truck average
            TransportMode::Air => 0.800,       // Air cargo average
        }
    }

    /// Typical mode transfer time in hours
    pub fn mode_transfer_hours(&self, to: &TransportMode) -> f64 {
        match (self, to) {
            (TransportMode::Maritime, TransportMode::Rail) => 24.0,
            (TransportMode::Maritime, TransportMode::Road) => 12.0,
            (TransportMode::Rail, TransportMode::Road) => 6.0,
            (TransportMode::Rail, TransportMode::Maritime) => 24.0,
            (TransportMode::Road, TransportMode::Rail) => 6.0,
            (TransportMode::Road, TransportMode::Maritime) => 12.0,
            (TransportMode::Air, _) | (_, TransportMode::Air) => 4.0,
            _ => 2.0,
        }
    }
}

/// A node in the transport network (port, terminal, hub)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransportNode {
    pub id: String,
    pub code: String,           // e.g., "NLRTM"
    pub name: String,
    pub country_code: String,
    pub lat: f64,
    pub lon: f64,
    pub modes: Vec<TransportMode>,
    pub avg_dwell_hours: f64,
}

/// An edge in the transport network (route segment)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransportEdge {
    pub id: String,
    pub code: String,
    pub mode: TransportMode,
    pub carrier_code: String,
    pub carrier_name: String,
    pub distance_km: f64,
    pub base_cost_usd: Decimal,
    pub cost_per_kg: Decimal,
    pub transit_hours: f64,
    pub carbon_per_tonne_km: f64,
    pub carrier_wage_cents: i32,
    pub carrier_safety_rating: i32,
    pub carrier_unionized: bool,
    pub carrier_sanctioned: bool,
    pub active: bool,
}

impl TransportEdge {
    /// Calculate cost for given weight
    pub fn calculate_cost(&self, weight_kg: f64) -> Decimal {
        self.base_cost_usd + self.cost_per_kg * Decimal::from_f64_retain(weight_kg).unwrap_or_default()
    }

    /// Calculate carbon emissions
    pub fn calculate_carbon(&self, weight_kg: f64) -> f64 {
        let tonnes = weight_kg / 1000.0;
        self.distance_km * tonnes * self.carbon_per_tonne_km
    }

    /// Calculate labor score (0.0 - 1.0)
    pub fn labor_score(&self, country_min_wage: i32) -> f64 {
        let wage_score = if country_min_wage > 0 {
            (self.carrier_wage_cents as f64 / (2.0 * country_min_wage as f64)).min(1.0)
        } else {
            0.5
        };
        let safety_score = self.carrier_safety_rating as f64 / 5.0;
        let union_score = if self.carrier_unionized { 1.0 } else { 0.5 };

        // Weighted average
        0.4 * wage_score + 0.4 * safety_score + 0.2 * union_score
    }
}

/// The transport graph
pub struct TransportGraph {
    /// The underlying directed graph
    graph: DiGraph<TransportNode, TransportEdge>,
    /// Map from node code to graph index
    node_index: HashMap<String, NodeIndex>,
    /// When the graph was last loaded
    pub loaded_at: DateTime<Utc>,
    /// Load time in milliseconds
    pub load_time_ms: u64,
}

impl TransportGraph {
    /// Create a new empty graph
    pub fn new() -> Self {
        TransportGraph {
            graph: DiGraph::new(),
            node_index: HashMap::new(),
            loaded_at: Utc::now(),
            load_time_ms: 0,
        }
    }

    /// Add a node to the graph
    pub fn add_node(&mut self, node: TransportNode) -> NodeIndex {
        let code = node.code.clone();
        let idx = self.graph.add_node(node);
        self.node_index.insert(code, idx);
        idx
    }

    /// Add an edge to the graph
    pub fn add_edge(&mut self, from_code: &str, to_code: &str, edge: TransportEdge) -> bool {
        if let (Some(&from_idx), Some(&to_idx)) = (
            self.node_index.get(from_code),
            self.node_index.get(to_code),
        ) {
            self.graph.add_edge(from_idx, to_idx, edge);
            true
        } else {
            false
        }
    }

    /// Get node by code
    pub fn get_node(&self, code: &str) -> Option<&TransportNode> {
        self.node_index.get(code).map(|&idx| &self.graph[idx])
    }

    /// Get node index by code
    pub fn get_node_index(&self, code: &str) -> Option<NodeIndex> {
        self.node_index.get(code).copied()
    }

    /// Number of nodes
    pub fn node_count(&self) -> usize {
        self.graph.node_count()
    }

    /// Number of edges
    pub fn edge_count(&self) -> usize {
        self.graph.edge_count()
    }

    /// Count edges by mode
    pub fn edge_count_by_mode(&self) -> HashMap<TransportMode, usize> {
        let mut counts = HashMap::new();
        for edge in self.graph.edge_weights() {
            *counts.entry(edge.mode).or_insert(0) += 1;
        }
        counts
    }

    /// Find shortest path by cost using Dijkstra
    pub fn shortest_path_by_cost(
        &self,
        from: &str,
        to: &str,
        weight_kg: f64,
    ) -> Option<(Vec<NodeIndex>, Decimal)> {
        let from_idx = self.get_node_index(from)?;
        let to_idx = self.get_node_index(to)?;

        let costs = dijkstra(&self.graph, from_idx, Some(to_idx), |e| {
            e.weight().calculate_cost(weight_kg)
        });

        costs.get(&to_idx).map(|&cost| {
            // Reconstruct path (simplified - real impl would track parents)
            (vec![from_idx, to_idx], cost)
        })
    }

    /// Get all edges from a node
    pub fn edges_from(&self, code: &str) -> Vec<(&TransportNode, &TransportEdge)> {
        let Some(&idx) = self.node_index.get(code) else {
            return vec![];
        };

        self.graph
            .edges(idx)
            .map(|e| (&self.graph[e.target()], e.weight()))
            .collect()
    }

    /// Get the underlying petgraph for advanced algorithms
    pub fn inner(&self) -> &DiGraph<TransportNode, TransportEdge> {
        &self.graph
    }

    /// Get all nodes
    pub fn nodes(&self) -> impl Iterator<Item = &TransportNode> {
        self.graph.node_weights()
    }

    /// Get all edges
    pub fn edges(&self) -> impl Iterator<Item = &TransportEdge> {
        self.graph.edge_weights()
    }
}

impl Default for TransportGraph {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_graph() {
        let mut graph = TransportGraph::new();

        let shanghai = TransportNode {
            id: "node-1".to_string(),
            code: "CNSHA".to_string(),
            name: "Shanghai".to_string(),
            country_code: "CN".to_string(),
            lat: 31.2304,
            lon: 121.4737,
            modes: vec![TransportMode::Maritime, TransportMode::Rail],
            avg_dwell_hours: 24.0,
        };

        let rotterdam = TransportNode {
            id: "node-2".to_string(),
            code: "NLRTM".to_string(),
            name: "Rotterdam".to_string(),
            country_code: "NL".to_string(),
            lat: 51.9225,
            lon: 4.4792,
            modes: vec![TransportMode::Maritime, TransportMode::Rail, TransportMode::Road],
            avg_dwell_hours: 18.0,
        };

        graph.add_node(shanghai);
        graph.add_node(rotterdam);

        let edge = TransportEdge {
            id: "edge-1".to_string(),
            code: "CNSHA-NLRTM-M".to_string(),
            mode: TransportMode::Maritime,
            carrier_code: "MAEU".to_string(),
            carrier_name: "Maersk".to_string(),
            distance_km: 19500.0,
            base_cost_usd: Decimal::from(5000),
            cost_per_kg: Decimal::new(1, 2), // 0.01
            transit_hours: 672.0, // ~28 days
            carbon_per_tonne_km: 0.015,
            carrier_wage_cents: 2500,
            carrier_safety_rating: 4,
            carrier_unionized: true,
            carrier_sanctioned: false,
            active: true,
        };

        assert!(graph.add_edge("CNSHA", "NLRTM", edge));
        assert_eq!(graph.node_count(), 2);
        assert_eq!(graph.edge_count(), 1);
    }
}

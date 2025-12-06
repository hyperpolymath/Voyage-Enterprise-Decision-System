//! Route Optimizer
//!
//! Multi-objective optimization for finding optimal multimodal routes.
//! Uses Pareto optimization to balance cost, time, carbon, and labor.

use crate::graph::{TransportGraph, TransportEdge, TransportMode, TransportNode};
use crate::constraints::{ConstraintEngine, ConstraintResult};

use petgraph::graph::NodeIndex;
use petgraph::visit::EdgeRef;
use rayon::prelude::*;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, BinaryHeap};
use std::cmp::Ordering;
use chrono::{DateTime, Utc, Duration};
use uuid::Uuid;

/// Optimization request parameters
#[derive(Debug, Clone)]
pub struct OptimizeRequest {
    pub shipment_id: String,
    pub origin_code: String,
    pub destination_code: String,
    pub weight_kg: f64,
    pub volume_m3: f64,
    pub pickup_after: DateTime<Utc>,
    pub deliver_by: DateTime<Utc>,
    pub max_cost_usd: Option<Decimal>,
    pub max_carbon_kg: Option<f64>,
    pub min_labor_score: Option<f64>,
    pub allowed_modes: HashSet<TransportMode>,
    pub excluded_carriers: HashSet<String>,
    pub max_routes: usize,
    pub max_segments: usize,
    pub cost_weight: f64,
    pub time_weight: f64,
    pub carbon_weight: f64,
    pub labor_weight: f64,
}

impl Default for OptimizeRequest {
    fn default() -> Self {
        OptimizeRequest {
            shipment_id: String::new(),
            origin_code: String::new(),
            destination_code: String::new(),
            weight_kg: 1000.0,
            volume_m3: 1.0,
            pickup_after: Utc::now(),
            deliver_by: Utc::now() + Duration::days(30),
            max_cost_usd: None,
            max_carbon_kg: None,
            min_labor_score: None,
            allowed_modes: HashSet::new(), // Empty = all allowed
            excluded_carriers: HashSet::new(),
            max_routes: 10,
            max_segments: 8,
            cost_weight: 0.4,
            time_weight: 0.3,
            carbon_weight: 0.2,
            labor_weight: 0.1,
        }
    }
}

/// A candidate route
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidateRoute {
    pub route_id: String,
    pub segments: Vec<RouteSegment>,
    pub total_cost_usd: Decimal,
    pub total_time_hours: f64,
    pub total_carbon_kg: f64,
    pub total_distance_km: f64,
    pub labor_score: f64,
    pub pareto_rank: u32,
    pub pareto_optimal: bool,
    pub weighted_score: f64,
    pub constraint_results: Vec<ConstraintResult>,
}

impl CandidateRoute {
    pub fn new() -> Self {
        CandidateRoute {
            route_id: Uuid::new_v4().to_string(),
            segments: Vec::new(),
            total_cost_usd: Decimal::ZERO,
            total_time_hours: 0.0,
            total_carbon_kg: 0.0,
            total_distance_km: 0.0,
            labor_score: 0.0,
            pareto_rank: 0,
            pareto_optimal: false,
            weighted_score: 0.0,
            constraint_results: Vec::new(),
        }
    }

    /// Calculate totals from segments
    pub fn recalculate_totals(&mut self) {
        self.total_cost_usd = self.segments.iter().map(|s| s.cost_usd).sum();
        self.total_time_hours = self.segments.iter().map(|s| s.transit_hours).sum();
        self.total_carbon_kg = self.segments.iter().map(|s| s.carbon_kg).sum();
        self.total_distance_km = self.segments.iter().map(|s| s.distance_km).sum();

        if !self.segments.is_empty() {
            self.labor_score = self.segments.iter().map(|s| s.labor_score).sum::<f64>()
                / self.segments.len() as f64;
        }
    }
}

/// A segment of a route
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouteSegment {
    pub segment_id: String,
    pub sequence: u32,
    pub from_node: String,
    pub to_node: String,
    pub mode: TransportMode,
    pub carrier_code: String,
    pub distance_km: f64,
    pub cost_usd: Decimal,
    pub transit_hours: f64,
    pub carbon_kg: f64,
    pub carrier_wage_cents: i32,
    pub labor_score: f64,
    pub departure_time: DateTime<Utc>,
    pub arrival_time: DateTime<Utc>,
}

/// Optimization result
#[derive(Debug)]
pub struct OptimizeResult {
    pub routes: Vec<CandidateRoute>,
    pub optimization_time_ms: u64,
    pub candidates_evaluated: usize,
}

/// State for path search
#[derive(Clone)]
struct SearchState {
    node: NodeIndex,
    path: Vec<(NodeIndex, TransportEdge)>,
    cost: Decimal,
    time_hours: f64,
    carbon_kg: f64,
    current_time: DateTime<Utc>,
}

impl Eq for SearchState {}

impl PartialEq for SearchState {
    fn eq(&self, other: &Self) -> bool {
        self.cost == other.cost
    }
}

impl Ord for SearchState {
    fn cmp(&self, other: &Self) -> Ordering {
        // Reverse for min-heap
        other.cost.cmp(&self.cost)
    }
}

impl PartialOrd for SearchState {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// Route optimizer
pub struct Optimizer {
    constraint_engine: ConstraintEngine,
}

impl Optimizer {
    pub fn new(constraint_engine: ConstraintEngine) -> Self {
        Optimizer { constraint_engine }
    }

    /// Optimize routes for a shipment request
    pub fn optimize(
        &self,
        graph: &TransportGraph,
        request: &OptimizeRequest,
    ) -> OptimizeResult {
        let start_time = std::time::Instant::now();

        // Find origin and destination nodes
        let Some(origin_idx) = graph.get_node_index(&request.origin_code) else {
            return OptimizeResult {
                routes: vec![],
                optimization_time_ms: start_time.elapsed().as_millis() as u64,
                candidates_evaluated: 0,
            };
        };

        let Some(dest_idx) = graph.get_node_index(&request.destination_code) else {
            return OptimizeResult {
                routes: vec![],
                optimization_time_ms: start_time.elapsed().as_millis() as u64,
                candidates_evaluated: 0,
            };
        };

        // Find candidate paths using modified Dijkstra (k-shortest paths)
        let candidates = self.find_k_shortest_paths(
            graph,
            origin_idx,
            dest_idx,
            request,
            request.max_routes * 3, // Find more than needed, filter later
        );

        let candidates_evaluated = candidates.len();

        // Convert paths to candidate routes with full details
        let mut routes: Vec<CandidateRoute> = candidates
            .into_par_iter()
            .map(|path| self.path_to_route(graph, &path, request))
            .collect();

        // Evaluate constraints
        for route in &mut routes {
            route.constraint_results = self.constraint_engine.evaluate_route(route, request);
        }

        // Filter out routes that fail hard constraints
        routes.retain(|r| {
            r.constraint_results
                .iter()
                .filter(|c| c.is_hard)
                .all(|c| c.passed)
        });

        // Calculate Pareto ranks
        self.calculate_pareto_ranks(&mut routes);

        // Calculate weighted scores
        for route in &mut routes {
            route.weighted_score = self.calculate_weighted_score(route, request, &routes);
        }

        // Sort by weighted score (lower is better)
        routes.sort_by(|a, b| {
            a.weighted_score
                .partial_cmp(&b.weighted_score)
                .unwrap_or(Ordering::Equal)
        });

        // Take top N routes
        routes.truncate(request.max_routes);

        OptimizeResult {
            routes,
            optimization_time_ms: start_time.elapsed().as_millis() as u64,
            candidates_evaluated,
        }
    }

    /// Find k-shortest paths using modified Dijkstra
    fn find_k_shortest_paths(
        &self,
        graph: &TransportGraph,
        origin: NodeIndex,
        destination: NodeIndex,
        request: &OptimizeRequest,
        k: usize,
    ) -> Vec<Vec<(NodeIndex, TransportEdge)>> {
        let inner_graph = graph.inner();
        let mut paths = Vec::new();
        let mut heap = BinaryHeap::new();

        // Initialize with starting state
        heap.push(SearchState {
            node: origin,
            path: Vec::new(),
            cost: Decimal::ZERO,
            time_hours: 0.0,
            carbon_kg: 0.0,
            current_time: request.pickup_after,
        });

        let mut visited_counts: HashMap<NodeIndex, usize> = HashMap::new();

        while let Some(state) = heap.pop() {
            // Count visits to this node
            let count = visited_counts.entry(state.node).or_insert(0);
            *count += 1;

            // Allow visiting each node up to k times for k-shortest paths
            if *count > k {
                continue;
            }

            // Check if we reached destination
            if state.node == destination && !state.path.is_empty() {
                paths.push(state.path.clone());
                if paths.len() >= k {
                    break;
                }
                continue;
            }

            // Limit path length
            if state.path.len() >= request.max_segments {
                continue;
            }

            // Explore neighbors
            for edge_ref in inner_graph.edges(state.node) {
                let edge = edge_ref.weight();
                let target = edge_ref.target();

                // Skip inactive edges
                if !edge.active {
                    continue;
                }

                // Check mode restrictions
                if !request.allowed_modes.is_empty()
                    && !request.allowed_modes.contains(&edge.mode)
                {
                    continue;
                }

                // Check carrier exclusions
                if request.excluded_carriers.contains(&edge.carrier_code) {
                    continue;
                }

                // Skip sanctioned carriers
                if edge.carrier_sanctioned {
                    continue;
                }

                // Calculate new state
                let new_cost = state.cost + edge.calculate_cost(request.weight_kg);
                let new_time = state.time_hours + edge.transit_hours;
                let new_carbon = state.carbon_kg + edge.calculate_carbon(request.weight_kg);

                // Add mode transfer time if changing modes
                let transfer_time = if let Some((_, last_edge)) = state.path.last() {
                    last_edge.mode.mode_transfer_hours(&edge.mode)
                } else {
                    0.0
                };
                let total_time = new_time + transfer_time;

                // Check time constraint
                let arrival = state.current_time + Duration::hours(total_time as i64);
                if arrival > request.deliver_by {
                    continue;
                }

                // Build new path
                let mut new_path = state.path.clone();
                new_path.push((target, edge.clone()));

                heap.push(SearchState {
                    node: target,
                    path: new_path,
                    cost: new_cost,
                    time_hours: total_time,
                    carbon_kg: new_carbon,
                    current_time: arrival,
                });
            }
        }

        paths
    }

    /// Convert a path to a full route with details
    fn path_to_route(
        &self,
        graph: &TransportGraph,
        path: &[(NodeIndex, TransportEdge)],
        request: &OptimizeRequest,
    ) -> CandidateRoute {
        let mut route = CandidateRoute::new();
        let mut current_time = request.pickup_after;
        let mut prev_mode: Option<TransportMode> = None;

        for (seq, (node_idx, edge)) in path.iter().enumerate() {
            let target_node = &graph.inner()[*node_idx];

            // Add transfer time if mode changed
            if let Some(pm) = prev_mode {
                if pm != edge.mode {
                    current_time = current_time + Duration::hours(pm.mode_transfer_hours(&edge.mode) as i64);
                }
            }

            let departure = current_time;
            let arrival = departure + Duration::hours(edge.transit_hours as i64);

            let segment = RouteSegment {
                segment_id: Uuid::new_v4().to_string(),
                sequence: seq as u32,
                from_node: if seq == 0 {
                    request.origin_code.clone()
                } else {
                    path[seq - 1].1.carrier_code.clone() // Simplified - should get from node
                },
                to_node: target_node.code.clone(),
                mode: edge.mode,
                carrier_code: edge.carrier_code.clone(),
                distance_km: edge.distance_km,
                cost_usd: edge.calculate_cost(request.weight_kg),
                transit_hours: edge.transit_hours,
                carbon_kg: edge.calculate_carbon(request.weight_kg),
                carrier_wage_cents: edge.carrier_wage_cents,
                labor_score: edge.labor_score(1500), // TODO: Get actual country min wage
                departure_time: departure,
                arrival_time: arrival,
            };

            route.segments.push(segment);
            current_time = arrival;
            prev_mode = Some(edge.mode);
        }

        route.recalculate_totals();
        route
    }

    /// Calculate Pareto ranks for routes
    fn calculate_pareto_ranks(&self, routes: &mut [CandidateRoute]) {
        let n = routes.len();
        let mut ranks = vec![0u32; n];
        let mut dominated_count = vec![0usize; n];

        // Calculate domination
        for i in 0..n {
            for j in 0..n {
                if i != j && self.dominates(&routes[i], &routes[j]) {
                    dominated_count[j] += 1;
                }
            }
        }

        // Assign ranks
        let mut current_rank = 1u32;
        let mut remaining: HashSet<usize> = (0..n).collect();

        while !remaining.is_empty() {
            // Find non-dominated in current set
            let non_dominated: Vec<usize> = remaining
                .iter()
                .filter(|&&i| dominated_count[i] == 0)
                .copied()
                .collect();

            if non_dominated.is_empty() {
                // Handle cycles - just assign next rank to remaining
                for &i in &remaining {
                    ranks[i] = current_rank;
                }
                break;
            }

            // Assign rank and remove from consideration
            for &i in &non_dominated {
                ranks[i] = current_rank;
                routes[i].pareto_optimal = current_rank == 1;
                remaining.remove(&i);

                // Reduce dominated counts for routes dominated by this one
                for &j in &remaining {
                    if self.dominates(&routes[i], &routes[j]) {
                        dominated_count[j] = dominated_count[j].saturating_sub(1);
                    }
                }
            }

            current_rank += 1;
        }

        // Apply ranks
        for (i, route) in routes.iter_mut().enumerate() {
            route.pareto_rank = ranks[i];
        }
    }

    /// Check if route A dominates route B (A is better in all objectives)
    fn dominates(&self, a: &CandidateRoute, b: &CandidateRoute) -> bool {
        let cost_better = a.total_cost_usd <= b.total_cost_usd;
        let time_better = a.total_time_hours <= b.total_time_hours;
        let carbon_better = a.total_carbon_kg <= b.total_carbon_kg;
        let labor_better = a.labor_score >= b.labor_score; // Higher is better

        let at_least_one_strictly = a.total_cost_usd < b.total_cost_usd
            || a.total_time_hours < b.total_time_hours
            || a.total_carbon_kg < b.total_carbon_kg
            || a.labor_score > b.labor_score;

        cost_better && time_better && carbon_better && labor_better && at_least_one_strictly
    }

    /// Calculate weighted score for ranking
    fn calculate_weighted_score(
        &self,
        route: &CandidateRoute,
        request: &OptimizeRequest,
        all_routes: &[CandidateRoute],
    ) -> f64 {
        // Normalize each objective to 0-1 range
        let max_cost = all_routes
            .iter()
            .map(|r| r.total_cost_usd)
            .max()
            .unwrap_or(Decimal::ONE);
        let max_time = all_routes
            .iter()
            .map(|r| r.total_time_hours)
            .fold(1.0f64, f64::max);
        let max_carbon = all_routes
            .iter()
            .map(|r| r.total_carbon_kg)
            .fold(1.0f64, f64::max);

        let cost_norm = if max_cost > Decimal::ZERO {
            (route.total_cost_usd / max_cost).to_string().parse::<f64>().unwrap_or(0.0)
        } else {
            0.0
        };
        let time_norm = if max_time > 0.0 {
            route.total_time_hours / max_time
        } else {
            0.0
        };
        let carbon_norm = if max_carbon > 0.0 {
            route.total_carbon_kg / max_carbon
        } else {
            0.0
        };
        let labor_norm = 1.0 - route.labor_score; // Invert so lower is better

        // Weighted sum (lower is better)
        request.cost_weight * cost_norm
            + request.time_weight * time_norm
            + request.carbon_weight * carbon_norm
            + request.labor_weight * labor_norm
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pareto_dominance() {
        let optimizer = Optimizer::new(ConstraintEngine::new());

        let route_a = CandidateRoute {
            total_cost_usd: Decimal::from(100),
            total_time_hours: 10.0,
            total_carbon_kg: 50.0,
            labor_score: 0.8,
            ..CandidateRoute::new()
        };

        let route_b = CandidateRoute {
            total_cost_usd: Decimal::from(150),
            total_time_hours: 15.0,
            total_carbon_kg: 60.0,
            labor_score: 0.7,
            ..CandidateRoute::new()
        };

        assert!(optimizer.dominates(&route_a, &route_b));
        assert!(!optimizer.dominates(&route_b, &route_a));
    }
}

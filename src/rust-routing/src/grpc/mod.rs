//! gRPC Service Implementation
//!
//! Exposes the optimizer via gRPC for integration with the Elixir API.

use crate::{AppState, graph::TransportMode, optimizer::{Optimizer, OptimizeRequest as OptimizerRequest, CandidateRoute}, constraints::ConstraintEngine};
use std::sync::Arc;
use tonic::{Request, Response, Status};
use chrono::DateTime;
use rust_decimal::Decimal;

// Include generated protobuf code
pub mod proto {
    tonic::include_proto!("veds.optimizer");
}

use proto::optimizer_service_server::{OptimizerService, OptimizerServiceServer};
use proto::*;

/// gRPC service implementation
pub struct OptimizerServiceImpl {
    state: Arc<AppState>,
}

impl OptimizerServiceImpl {
    pub fn new(state: Arc<AppState>) -> Self {
        OptimizerServiceImpl { state }
    }
}

#[tonic::async_trait]
impl OptimizerService for OptimizerServiceImpl {
    async fn optimize_routes(
        &self,
        request: Request<OptimizeRequest>,
    ) -> Result<Response<OptimizeResponse>, Status> {
        let req = request.into_inner();

        // Parse request into internal format
        let internal_request = match parse_optimize_request(&req) {
            Ok(r) => r,
            Err(e) => {
                return Ok(Response::new(OptimizeResponse {
                    success: false,
                    error_message: e.to_string(),
                    routes: vec![],
                    optimization_time_ms: 0,
                    candidates_evaluated: 0,
                }));
            }
        };

        // Get graph read lock
        let graph = self.state.graph.read().await;

        // Create optimizer with constraint engine
        let constraint_engine = ConstraintEngine::new(); // TODO: Load cache from Dragonfly
        let optimizer = Optimizer::new(constraint_engine);

        // Run optimization
        let result = optimizer.optimize(&graph, &internal_request);

        // Convert to response
        let routes: Vec<Route> = result
            .routes
            .into_iter()
            .map(route_to_proto)
            .collect();

        Ok(Response::new(OptimizeResponse {
            success: true,
            error_message: String::new(),
            routes,
            optimization_time_ms: result.optimization_time_ms as i64,
            candidates_evaluated: result.candidates_evaluated as i32,
        }))
    }

    async fn evaluate_constraints(
        &self,
        request: Request<EvaluateRequest>,
    ) -> Result<Response<EvaluateResponse>, Status> {
        let req = request.into_inner();

        // Parse route from request
        let Some(proto_route) = req.route else {
            return Err(Status::invalid_argument("Route is required"));
        };

        let route = match parse_proto_route(&proto_route) {
            Ok(r) => r,
            Err(e) => return Err(Status::invalid_argument(e.to_string())),
        };

        // Create constraint engine and evaluate
        let constraint_engine = ConstraintEngine::new();
        let default_request = OptimizerRequest::default();
        let results = constraint_engine.evaluate_route(&route, &default_request);

        let all_hard_passed = results.iter().filter(|r| r.is_hard).all(|r| r.passed);
        let overall_score = if results.is_empty() {
            1.0
        } else {
            results.iter().map(|r| r.score).sum::<f64>() / results.len() as f64
        };

        let proto_results: Vec<ConstraintResult> = results
            .into_iter()
            .map(|r| ConstraintResult {
                constraint_id: r.constraint_id,
                constraint_type: r.constraint_type.to_string(),
                passed: r.passed,
                is_hard: r.is_hard,
                score: r.score,
                message: r.message,
            })
            .collect();

        Ok(Response::new(EvaluateResponse {
            success: true,
            all_hard_passed,
            overall_score,
            results: proto_results,
        }))
    }

    async fn get_graph_status(
        &self,
        _request: Request<GraphStatusRequest>,
    ) -> Result<Response<GraphStatusResponse>, Status> {
        let graph = self.state.graph.read().await;

        let mode_counts: Vec<ModeCount> = graph
            .edge_count_by_mode()
            .into_iter()
            .map(|(mode, count)| ModeCount {
                mode: mode.to_string(),
                count: count as i64,
            })
            .collect();

        Ok(Response::new(GraphStatusResponse {
            node_count: graph.node_count() as i64,
            edge_count: graph.edge_count() as i64,
            last_loaded: graph.loaded_at.to_rfc3339(),
            load_time_ms: graph.load_time_ms as i64,
            mode_counts,
        }))
    }

    async fn reload_graph(
        &self,
        _request: Request<ReloadGraphRequest>,
    ) -> Result<Response<ReloadGraphResponse>, Status> {
        let start = std::time::Instant::now();

        match crate::db::load_graph_from_surrealdb(&self.state.config).await {
            Ok(new_graph) => {
                let mut graph = self.state.graph.write().await;
                *graph = new_graph;

                Ok(Response::new(ReloadGraphResponse {
                    success: true,
                    message: format!(
                        "Loaded {} nodes, {} edges",
                        graph.node_count(),
                        graph.edge_count()
                    ),
                    load_time_ms: start.elapsed().as_millis() as i64,
                }))
            }
            Err(e) => Ok(Response::new(ReloadGraphResponse {
                success: false,
                message: e.to_string(),
                load_time_ms: start.elapsed().as_millis() as i64,
            })),
        }
    }
}

/// Create the gRPC server
pub fn optimizer_service_server(
    state: Arc<AppState>,
) -> OptimizerServiceServer<OptimizerServiceImpl> {
    OptimizerServiceServer::new(OptimizerServiceImpl::new(state))
}

/// Parse protobuf request to internal format
fn parse_optimize_request(req: &OptimizeRequest) -> Result<OptimizerRequest, anyhow::Error> {
    let pickup_after = DateTime::parse_from_rfc3339(&req.pickup_after)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .unwrap_or_else(|_| chrono::Utc::now());

    let deliver_by = DateTime::parse_from_rfc3339(&req.deliver_by)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .unwrap_or_else(|_| chrono::Utc::now() + chrono::Duration::days(30));

    let allowed_modes: std::collections::HashSet<TransportMode> = req
        .allowed_modes
        .iter()
        .filter_map(|m| match m.to_uppercase().as_str() {
            "MARITIME" => Some(TransportMode::Maritime),
            "RAIL" => Some(TransportMode::Rail),
            "ROAD" => Some(TransportMode::Road),
            "AIR" => Some(TransportMode::Air),
            _ => None,
        })
        .collect();

    Ok(OptimizerRequest {
        shipment_id: req.shipment_id.clone(),
        origin_code: req.origin_port.clone(),
        destination_code: req.destination_port.clone(),
        weight_kg: req.weight_kg,
        volume_m3: req.volume_m3,
        pickup_after,
        deliver_by,
        max_cost_usd: req.max_cost_usd.map(|v| Decimal::from_f64_retain(v).unwrap_or(Decimal::MAX)),
        max_carbon_kg: req.max_carbon_kg,
        min_labor_score: req.min_labor_score,
        allowed_modes,
        excluded_carriers: req.excluded_carriers.iter().cloned().collect(),
        max_routes: req.max_routes as usize,
        max_segments: req.max_segments as usize,
        cost_weight: req.cost_weight,
        time_weight: req.time_weight,
        carbon_weight: req.carbon_weight,
        labor_weight: req.labor_weight,
    })
}

/// Convert internal route to protobuf
fn route_to_proto(route: CandidateRoute) -> Route {
    let segments: Vec<Segment> = route
        .segments
        .into_iter()
        .map(|s| Segment {
            segment_id: s.segment_id,
            sequence: s.sequence as i32,
            from_node: s.from_node,
            to_node: s.to_node,
            mode: s.mode.to_string(),
            carrier_code: s.carrier_code,
            distance_km: s.distance_km,
            cost_usd: s.cost_usd.to_string().parse().unwrap_or(0.0),
            transit_hours: s.transit_hours,
            carbon_kg: s.carbon_kg,
            carrier_wage_cents: s.carrier_wage_cents,
            departure_time: s.departure_time.to_rfc3339(),
            arrival_time: s.arrival_time.to_rfc3339(),
        })
        .collect();

    let constraint_results: Vec<ConstraintResult> = route
        .constraint_results
        .into_iter()
        .map(|r| ConstraintResult {
            constraint_id: r.constraint_id,
            constraint_type: r.constraint_type.to_string(),
            passed: r.passed,
            is_hard: r.is_hard,
            score: r.score,
            message: r.message,
        })
        .collect();

    Route {
        route_id: route.route_id,
        segments,
        total_cost_usd: route.total_cost_usd.to_string().parse().unwrap_or(0.0),
        total_time_hours: route.total_time_hours,
        total_carbon_kg: route.total_carbon_kg,
        total_distance_km: route.total_distance_km,
        labor_score: route.labor_score,
        pareto_rank: route.pareto_rank as i32,
        pareto_optimal: route.pareto_optimal,
        weighted_score: route.weighted_score,
        constraint_results,
    }
}

/// Parse protobuf route to internal format
fn parse_proto_route(proto: &Route) -> Result<CandidateRoute, anyhow::Error> {
    use crate::optimizer::RouteSegment;

    let segments: Vec<RouteSegment> = proto
        .segments
        .iter()
        .map(|s| {
            let mode = match s.mode.to_uppercase().as_str() {
                "MARITIME" => TransportMode::Maritime,
                "RAIL" => TransportMode::Rail,
                "ROAD" => TransportMode::Road,
                "AIR" => TransportMode::Air,
                _ => TransportMode::Road,
            };

            RouteSegment {
                segment_id: s.segment_id.clone(),
                sequence: s.sequence as u32,
                from_node: s.from_node.clone(),
                to_node: s.to_node.clone(),
                mode,
                carrier_code: s.carrier_code.clone(),
                distance_km: s.distance_km,
                cost_usd: Decimal::from_f64_retain(s.cost_usd).unwrap_or(Decimal::ZERO),
                transit_hours: s.transit_hours,
                carbon_kg: s.carbon_kg,
                carrier_wage_cents: s.carrier_wage_cents,
                labor_score: 0.8, // Default
                departure_time: DateTime::parse_from_rfc3339(&s.departure_time)
                    .map(|dt| dt.with_timezone(&chrono::Utc))
                    .unwrap_or_else(|_| chrono::Utc::now()),
                arrival_time: DateTime::parse_from_rfc3339(&s.arrival_time)
                    .map(|dt| dt.with_timezone(&chrono::Utc))
                    .unwrap_or_else(|_| chrono::Utc::now()),
            }
        })
        .collect();

    let mut route = CandidateRoute {
        route_id: proto.route_id.clone(),
        segments,
        total_cost_usd: Decimal::from_f64_retain(proto.total_cost_usd).unwrap_or(Decimal::ZERO),
        total_time_hours: proto.total_time_hours,
        total_carbon_kg: proto.total_carbon_kg,
        total_distance_km: proto.total_distance_km,
        labor_score: proto.labor_score,
        pareto_rank: proto.pareto_rank as u32,
        pareto_optimal: proto.pareto_optimal,
        weighted_score: proto.weighted_score,
        constraint_results: vec![],
    };

    route.recalculate_totals();
    Ok(route)
}

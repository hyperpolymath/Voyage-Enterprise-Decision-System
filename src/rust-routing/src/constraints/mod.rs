//! Constraint Engine
//!
//! Evaluates hard and soft constraints on routes.
//! Uses cached constraint rules from Dragonfly for fast evaluation.

use crate::optimizer::{CandidateRoute, OptimizeRequest, RouteSegment};
use serde::{Deserialize, Serialize};

/// Result of constraint evaluation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConstraintResult {
    pub constraint_id: String,
    pub constraint_type: ConstraintType,
    pub passed: bool,
    pub is_hard: bool,
    pub score: f64,   // 0.0 - 1.0 for soft constraints
    pub message: String,
}

/// Types of constraints
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum ConstraintType {
    Wage,
    Carbon,
    Time,
    Cost,
    Sanction,
    Mode,
    Custom,
}

impl std::fmt::Display for ConstraintType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConstraintType::Wage => write!(f, "WAGE"),
            ConstraintType::Carbon => write!(f, "CARBON"),
            ConstraintType::Time => write!(f, "TIME"),
            ConstraintType::Cost => write!(f, "COST"),
            ConstraintType::Sanction => write!(f, "SANCTION"),
            ConstraintType::Mode => write!(f, "MODE"),
            ConstraintType::Custom => write!(f, "CUSTOM"),
        }
    }
}

/// Cached constraint lookup tables (loaded from Dragonfly)
#[derive(Debug, Clone, Default)]
pub struct ConstraintCache {
    /// Minimum wage by country code (cents/hour)
    pub min_wages: std::collections::HashMap<String, i32>,
    /// Maximum weekly hours by region
    pub max_hours: std::collections::HashMap<String, i32>,
    /// Set of sanctioned carrier codes
    pub sanctioned_carriers: std::collections::HashSet<String>,
}

/// Constraint engine
pub struct ConstraintEngine {
    cache: ConstraintCache,
}

impl ConstraintEngine {
    pub fn new() -> Self {
        ConstraintEngine {
            cache: ConstraintCache::default(),
        }
    }

    /// Create with pre-loaded cache
    pub fn with_cache(cache: ConstraintCache) -> Self {
        ConstraintEngine { cache }
    }

    /// Update the constraint cache
    pub fn update_cache(&mut self, cache: ConstraintCache) {
        self.cache = cache;
    }

    /// Evaluate all constraints for a route
    pub fn evaluate_route(
        &self,
        route: &CandidateRoute,
        request: &OptimizeRequest,
    ) -> Vec<ConstraintResult> {
        let mut results = Vec::new();

        // Hard constraints
        results.push(self.check_sanction_constraint(route));
        results.push(self.check_wage_constraint(route));
        results.push(self.check_time_constraint(route, request));

        // Soft constraints (from request)
        if let Some(max_cost) = &request.max_cost_usd {
            results.push(self.check_cost_constraint(route, *max_cost));
        }

        if let Some(max_carbon) = request.max_carbon_kg {
            results.push(self.check_carbon_constraint(route, max_carbon));
        }

        if let Some(min_labor) = request.min_labor_score {
            results.push(self.check_labor_constraint(route, min_labor));
        }

        results
    }

    /// Check sanction constraint (HARD)
    fn check_sanction_constraint(&self, route: &CandidateRoute) -> ConstraintResult {
        let mut violations = Vec::new();

        for segment in &route.segments {
            if self.cache.sanctioned_carriers.contains(&segment.carrier_code) {
                violations.push(segment.carrier_code.clone());
            }
        }

        let passed = violations.is_empty();
        let message = if passed {
            "No sanctioned carriers".to_string()
        } else {
            format!("Sanctioned carriers: {}", violations.join(", "))
        };

        ConstraintResult {
            constraint_id: "sanction-check".to_string(),
            constraint_type: ConstraintType::Sanction,
            passed,
            is_hard: true,
            score: if passed { 1.0 } else { 0.0 },
            message,
        }
    }

    /// Check wage constraint (HARD)
    fn check_wage_constraint(&self, route: &CandidateRoute) -> ConstraintResult {
        let mut violations = Vec::new();

        for segment in &route.segments {
            // Get minimum wage for the segment's operating country
            // For now, use a default minimum if not in cache
            let min_wage = self.cache.min_wages
                .get(&segment.to_node)
                .copied()
                .unwrap_or(800); // Default $8/hour

            if segment.carrier_wage_cents < min_wage {
                violations.push(format!(
                    "Segment {}: wage {} < min {}",
                    segment.sequence, segment.carrier_wage_cents, min_wage
                ));
            }
        }

        let passed = violations.is_empty();
        let message = if passed {
            "All segments meet wage requirements".to_string()
        } else {
            violations.join("; ")
        };

        ConstraintResult {
            constraint_id: "wage-minimum".to_string(),
            constraint_type: ConstraintType::Wage,
            passed,
            is_hard: true,
            score: if passed { 1.0 } else { 0.0 },
            message,
        }
    }

    /// Check time constraint (HARD)
    fn check_time_constraint(
        &self,
        route: &CandidateRoute,
        request: &OptimizeRequest,
    ) -> ConstraintResult {
        let max_hours = (request.deliver_by - request.pickup_after).num_hours() as f64;
        let passed = route.total_time_hours <= max_hours;

        let message = if passed {
            format!(
                "Route time {:.1}h within window {:.1}h",
                route.total_time_hours, max_hours
            )
        } else {
            format!(
                "Route time {:.1}h exceeds window {:.1}h by {:.1}h",
                route.total_time_hours,
                max_hours,
                route.total_time_hours - max_hours
            )
        };

        ConstraintResult {
            constraint_id: "time-window".to_string(),
            constraint_type: ConstraintType::Time,
            passed,
            is_hard: true,
            score: if passed { 1.0 } else { 0.0 },
            message,
        }
    }

    /// Check cost constraint (SOFT)
    fn check_cost_constraint(
        &self,
        route: &CandidateRoute,
        max_cost: rust_decimal::Decimal,
    ) -> ConstraintResult {
        let passed = route.total_cost_usd <= max_cost;
        let score = if max_cost > rust_decimal::Decimal::ZERO {
            let ratio = route.total_cost_usd / max_cost;
            (1.0 - ratio.to_string().parse::<f64>().unwrap_or(1.0)).max(0.0)
        } else {
            0.0
        };

        let message = format!(
            "Cost ${} vs budget ${}",
            route.total_cost_usd, max_cost
        );

        ConstraintResult {
            constraint_id: "cost-budget".to_string(),
            constraint_type: ConstraintType::Cost,
            passed,
            is_hard: false,
            score,
            message,
        }
    }

    /// Check carbon constraint (SOFT)
    fn check_carbon_constraint(
        &self,
        route: &CandidateRoute,
        max_carbon: f64,
    ) -> ConstraintResult {
        let passed = route.total_carbon_kg <= max_carbon;
        let score = if max_carbon > 0.0 {
            (1.0 - route.total_carbon_kg / max_carbon).max(0.0)
        } else {
            0.0
        };

        let message = format!(
            "Carbon {:.1}kg vs budget {:.1}kg",
            route.total_carbon_kg, max_carbon
        );

        ConstraintResult {
            constraint_id: "carbon-budget".to_string(),
            constraint_type: ConstraintType::Carbon,
            passed,
            is_hard: false,
            score,
            message,
        }
    }

    /// Check labor score constraint (SOFT)
    fn check_labor_constraint(
        &self,
        route: &CandidateRoute,
        min_score: f64,
    ) -> ConstraintResult {
        let passed = route.labor_score >= min_score;
        let score = route.labor_score;

        let message = format!(
            "Labor score {:.2} vs minimum {:.2}",
            route.labor_score, min_score
        );

        ConstraintResult {
            constraint_id: "labor-minimum".to_string(),
            constraint_type: ConstraintType::Wage,
            passed,
            is_hard: false,
            score,
            message,
        }
    }
}

impl Default for ConstraintEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal::Decimal;

    #[test]
    fn test_sanction_check() {
        let mut cache = ConstraintCache::default();
        cache.sanctioned_carriers.insert("BADCO".to_string());

        let engine = ConstraintEngine::with_cache(cache);

        let mut route = CandidateRoute::new();
        route.segments.push(RouteSegment {
            segment_id: "s1".to_string(),
            sequence: 0,
            from_node: "A".to_string(),
            to_node: "B".to_string(),
            mode: crate::graph::TransportMode::Maritime,
            carrier_code: "GOODCO".to_string(),
            distance_km: 1000.0,
            cost_usd: Decimal::from(100),
            transit_hours: 24.0,
            carbon_kg: 50.0,
            carrier_wage_cents: 2000,
            labor_score: 0.8,
            departure_time: chrono::Utc::now(),
            arrival_time: chrono::Utc::now(),
        });

        let result = engine.check_sanction_constraint(&route);
        assert!(result.passed);

        // Add sanctioned carrier
        route.segments[0].carrier_code = "BADCO".to_string();
        let result = engine.check_sanction_constraint(&route);
        assert!(!result.passed);
    }
}

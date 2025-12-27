-- SPDX-License-Identifier: MIT OR AGPL-3.0
-- VEDS SurrealDB Schema
-- Transport Network Domain Model

-- =============================================================================
-- NAMESPACE & DATABASE SETUP
-- =============================================================================

USE NS veds;
USE DB production;

-- =============================================================================
-- TABLES: REFERENCE DATA
-- =============================================================================

-- Countries with economic/regulatory data
DEFINE TABLE country SCHEMAFULL;
DEFINE FIELD code ON country TYPE string ASSERT $value != NONE AND string::len($value) == 2;
DEFINE FIELD name ON country TYPE string ASSERT $value != NONE;
DEFINE FIELD region ON country TYPE string;
DEFINE FIELD min_wage_cents_hourly ON country TYPE option<int>;
DEFINE FIELD carbon_tax_per_tonne ON country TYPE option<decimal>;
DEFINE FIELD timezone ON country TYPE string;
DEFINE FIELD created_at ON country TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON country TYPE datetime VALUE time::now();
DEFINE INDEX idx_country_code ON country FIELDS code UNIQUE;

-- Ports/Terminals (physical locations)
DEFINE TABLE port SCHEMAFULL;
DEFINE FIELD unlocode ON port TYPE string ASSERT $value != NONE AND string::len($value) == 5;
DEFINE FIELD name ON port TYPE string ASSERT $value != NONE;
DEFINE FIELD country ON port TYPE record<country> ASSERT $value != NONE;
DEFINE FIELD location ON port TYPE option<geometry<point>>;
DEFINE FIELD timezone ON port TYPE string;
DEFINE FIELD port_type ON port TYPE string ASSERT $value IN ["sea", "rail", "road", "air", "multimodal"];
DEFINE FIELD avg_dwell_hours ON port TYPE decimal DEFAULT 24.0;
DEFINE FIELD congestion_factor ON port TYPE decimal DEFAULT 1.0;
DEFINE FIELD active ON port TYPE bool DEFAULT true;
DEFINE FIELD created_at ON port TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON port TYPE datetime VALUE time::now();
DEFINE INDEX idx_port_unlocode ON port FIELDS unlocode UNIQUE;
DEFINE INDEX idx_port_country ON port FIELDS country;
DEFINE INDEX idx_port_active ON port FIELDS active;

-- Carriers (shipping lines, trucking companies, etc.)
DEFINE TABLE carrier SCHEMAFULL;
DEFINE FIELD code ON carrier TYPE string ASSERT $value != NONE;
DEFINE FIELD name ON carrier TYPE string ASSERT $value != NONE;
DEFINE FIELD carrier_type ON carrier TYPE string ASSERT $value IN ["shipping", "trucking", "rail", "air", "freight_forwarder"];
DEFINE FIELD country ON carrier TYPE record<country>;
DEFINE FIELD avg_wage_cents_hourly ON carrier TYPE option<int>;
DEFINE FIELD safety_rating ON carrier TYPE int DEFAULT 3 ASSERT $value >= 1 AND $value <= 5;
DEFINE FIELD unionized ON carrier TYPE bool DEFAULT false;
DEFINE FIELD sanctioned ON carrier TYPE bool DEFAULT false;
DEFINE FIELD sustainability_score ON carrier TYPE option<decimal>;
DEFINE FIELD active ON carrier TYPE bool DEFAULT true;
DEFINE FIELD created_at ON carrier TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON carrier TYPE datetime VALUE time::now();
DEFINE INDEX idx_carrier_code ON carrier FIELDS code UNIQUE;
DEFINE INDEX idx_carrier_sanctioned ON carrier FIELDS sanctioned;

-- =============================================================================
-- TABLES: TRANSPORT NETWORK GRAPH
-- =============================================================================

-- Transport nodes (graph vertices)
DEFINE TABLE transport_node SCHEMAFULL;
DEFINE FIELD code ON transport_node TYPE string ASSERT $value != NONE;
DEFINE FIELD port ON transport_node TYPE record<port> ASSERT $value != NONE;
DEFINE FIELD node_type ON transport_node TYPE string ASSERT $value IN ["origin", "destination", "hub", "transfer"];
DEFINE FIELD modes ON transport_node TYPE array<string>;
DEFINE FIELD capacity_teu_day ON transport_node TYPE option<int>;
DEFINE FIELD handling_cost_usd ON transport_node TYPE decimal DEFAULT 0;
DEFINE FIELD active ON transport_node TYPE bool DEFAULT true;
DEFINE FIELD created_at ON transport_node TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON transport_node TYPE datetime VALUE time::now();
DEFINE INDEX idx_transport_node_code ON transport_node FIELDS code UNIQUE;
DEFINE INDEX idx_transport_node_active ON transport_node FIELDS active;

-- Transport edges (graph edges / route segments)
DEFINE TABLE transport_edge SCHEMAFULL;
DEFINE FIELD code ON transport_edge TYPE string ASSERT $value != NONE;
DEFINE FIELD from_node ON transport_edge TYPE record<transport_node> ASSERT $value != NONE;
DEFINE FIELD to_node ON transport_edge TYPE record<transport_node> ASSERT $value != NONE;
DEFINE FIELD carrier ON transport_edge TYPE record<carrier>;
DEFINE FIELD mode ON transport_edge TYPE string ASSERT $value IN ["MARITIME", "RAIL", "ROAD", "AIR"];
DEFINE FIELD distance_km ON transport_edge TYPE decimal ASSERT $value > 0;
DEFINE FIELD base_cost_usd ON transport_edge TYPE decimal DEFAULT 0;
DEFINE FIELD cost_per_kg_usd ON transport_edge TYPE decimal DEFAULT 0;
DEFINE FIELD transit_hours ON transport_edge TYPE decimal ASSERT $value > 0;
DEFINE FIELD carbon_kg_per_tonne_km ON transport_edge TYPE decimal;
DEFINE FIELD frequency_per_week ON transport_edge TYPE int DEFAULT 7;
DEFINE FIELD capacity_kg ON transport_edge TYPE option<int>;
DEFINE FIELD reliability_score ON transport_edge TYPE decimal DEFAULT 0.95;
DEFINE FIELD active ON transport_edge TYPE bool DEFAULT true;
DEFINE FIELD valid_from ON transport_edge TYPE datetime DEFAULT time::now();
DEFINE FIELD valid_until ON transport_edge TYPE option<datetime>;
DEFINE FIELD created_at ON transport_edge TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON transport_edge TYPE datetime VALUE time::now();
DEFINE INDEX idx_transport_edge_code ON transport_edge FIELDS code UNIQUE;
DEFINE INDEX idx_transport_edge_from ON transport_edge FIELDS from_node;
DEFINE INDEX idx_transport_edge_to ON transport_edge FIELDS to_node;
DEFINE INDEX idx_transport_edge_mode ON transport_edge FIELDS mode;
DEFINE INDEX idx_transport_edge_active ON transport_edge FIELDS active;
DEFINE INDEX idx_transport_edge_carrier ON transport_edge FIELDS carrier;

-- =============================================================================
-- TABLES: SHIPMENTS & ROUTES
-- =============================================================================

-- Shipments (cargo to be moved)
DEFINE TABLE shipment SCHEMAFULL;
DEFINE FIELD external_id ON shipment TYPE string;
DEFINE FIELD customer_id ON shipment TYPE string ASSERT $value != NONE;
DEFINE FIELD origin ON shipment TYPE record<transport_node> ASSERT $value != NONE;
DEFINE FIELD destination ON shipment TYPE record<transport_node> ASSERT $value != NONE;
DEFINE FIELD weight_kg ON shipment TYPE decimal ASSERT $value > 0;
DEFINE FIELD volume_cbm ON shipment TYPE option<decimal>;
DEFINE FIELD commodity_code ON shipment TYPE string;
DEFINE FIELD commodity_desc ON shipment TYPE string;
DEFINE FIELD hazmat_class ON shipment TYPE option<string>;
DEFINE FIELD temperature_controlled ON shipment TYPE bool DEFAULT false;
DEFINE FIELD required_temp_min ON shipment TYPE option<decimal>;
DEFINE FIELD required_temp_max ON shipment TYPE option<decimal>;
DEFINE FIELD earliest_pickup ON shipment TYPE datetime;
DEFINE FIELD latest_delivery ON shipment TYPE datetime;
DEFINE FIELD priority ON shipment TYPE string DEFAULT "normal" ASSERT $value IN ["low", "normal", "high", "urgent"];
DEFINE FIELD status ON shipment TYPE string DEFAULT "pending" ASSERT $value IN ["pending", "planned", "in_transit", "delivered", "cancelled"];
DEFINE FIELD max_cost_usd ON shipment TYPE option<decimal>;
DEFINE FIELD max_carbon_kg ON shipment TYPE option<decimal>;
DEFINE FIELD created_at ON shipment TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON shipment TYPE datetime VALUE time::now();
DEFINE INDEX idx_shipment_external ON shipment FIELDS external_id UNIQUE;
DEFINE INDEX idx_shipment_customer ON shipment FIELDS customer_id;
DEFINE INDEX idx_shipment_status ON shipment FIELDS status;
DEFINE INDEX idx_shipment_deadline ON shipment FIELDS latest_delivery;

-- Routes (planned paths for shipments)
DEFINE TABLE route SCHEMAFULL;
DEFINE FIELD shipment ON route TYPE record<shipment> ASSERT $value != NONE;
DEFINE FIELD status ON route TYPE string DEFAULT "draft" ASSERT $value IN ["draft", "proposed", "accepted", "executing", "completed", "failed"];
DEFINE FIELD segments ON route TYPE array<record<route_segment>>;
DEFINE FIELD total_cost_usd ON route TYPE decimal DEFAULT 0;
DEFINE FIELD total_carbon_kg ON route TYPE decimal DEFAULT 0;
DEFINE FIELD total_transit_hours ON route TYPE decimal DEFAULT 0;
DEFINE FIELD total_distance_km ON route TYPE decimal DEFAULT 0;
DEFINE FIELD labor_score ON route TYPE decimal DEFAULT 0;
DEFINE FIELD constraint_score ON route TYPE decimal DEFAULT 0;
DEFINE FIELD pareto_optimal ON route TYPE bool DEFAULT false;
DEFINE FIELD selected ON route TYPE bool DEFAULT false;
DEFINE FIELD departure_time ON route TYPE datetime;
DEFINE FIELD arrival_time ON route TYPE datetime;
DEFINE FIELD created_at ON route TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON route TYPE datetime VALUE time::now();
DEFINE INDEX idx_route_shipment ON route FIELDS shipment;
DEFINE INDEX idx_route_status ON route FIELDS status;
DEFINE INDEX idx_route_pareto ON route FIELDS pareto_optimal;

-- Route segments (individual legs of a route)
DEFINE TABLE route_segment SCHEMAFULL;
DEFINE FIELD route ON route_segment TYPE record<route>;
DEFINE FIELD edge ON route_segment TYPE record<transport_edge>;
DEFINE FIELD sequence ON route_segment TYPE int ASSERT $value >= 0;
DEFINE FIELD departure_time ON route_segment TYPE datetime;
DEFINE FIELD arrival_time ON route_segment TYPE datetime;
DEFINE FIELD cost_usd ON route_segment TYPE decimal DEFAULT 0;
DEFINE FIELD carbon_kg ON route_segment TYPE decimal DEFAULT 0;
DEFINE FIELD status ON route_segment TYPE string DEFAULT "pending" ASSERT $value IN ["pending", "departed", "in_transit", "arrived", "delayed", "cancelled"];
DEFINE FIELD delay_hours ON route_segment TYPE decimal DEFAULT 0;
DEFINE FIELD created_at ON route_segment TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON route_segment TYPE datetime VALUE time::now();
DEFINE INDEX idx_segment_route ON route_segment FIELDS route;
DEFINE INDEX idx_segment_edge ON route_segment FIELDS edge;
DEFINE INDEX idx_segment_seq ON route_segment FIELDS route, sequence UNIQUE;

-- =============================================================================
-- TABLES: REAL-TIME DATA
-- =============================================================================

-- Position updates (tracking)
DEFINE TABLE position_update SCHEMAFULL;
DEFINE FIELD shipment ON position_update TYPE record<shipment>;
DEFINE FIELD segment ON position_update TYPE option<record<route_segment>>;
DEFINE FIELD location ON position_update TYPE geometry<point>;
DEFINE FIELD speed_knots ON position_update TYPE option<decimal>;
DEFINE FIELD heading ON position_update TYPE option<decimal>;
DEFINE FIELD source ON position_update TYPE string ASSERT $value IN ["ais", "gps", "manual", "iot"];
DEFINE FIELD timestamp ON position_update TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_position_shipment ON position_update FIELDS shipment;
DEFINE INDEX idx_position_time ON position_update FIELDS timestamp;

-- Rate quotes (pricing cache)
DEFINE TABLE rate_quote SCHEMAFULL;
DEFINE FIELD edge ON rate_quote TYPE record<transport_edge>;
DEFINE FIELD carrier ON rate_quote TYPE record<carrier>;
DEFINE FIELD weight_min_kg ON rate_quote TYPE decimal;
DEFINE FIELD weight_max_kg ON rate_quote TYPE decimal;
DEFINE FIELD base_rate_usd ON rate_quote TYPE decimal;
DEFINE FIELD per_kg_rate_usd ON rate_quote TYPE decimal;
DEFINE FIELD fuel_surcharge_pct ON rate_quote TYPE decimal DEFAULT 0;
DEFINE FIELD valid_from ON rate_quote TYPE datetime;
DEFINE FIELD valid_until ON rate_quote TYPE datetime;
DEFINE FIELD created_at ON rate_quote TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_rate_edge ON rate_quote FIELDS edge;
DEFINE INDEX idx_rate_validity ON rate_quote FIELDS valid_from, valid_until;

-- =============================================================================
-- GRAPH RELATIONS (for traversal queries)
-- =============================================================================

-- Define the graph relation for transport network
DEFINE TABLE connects TYPE RELATION FROM transport_node TO transport_node SCHEMAFULL;
DEFINE FIELD edge ON connects TYPE record<transport_edge>;
DEFINE FIELD mode ON connects TYPE string;
DEFINE FIELD distance_km ON connects TYPE decimal;
DEFINE FIELD transit_hours ON connects TYPE decimal;

-- =============================================================================
-- FUNCTIONS: UTILITY
-- =============================================================================

-- Calculate haversine distance between two points
DEFINE FUNCTION fn::haversine($lat1: decimal, $lon1: decimal, $lat2: decimal, $lon2: decimal) {
    LET $R = 6371.0; -- Earth radius in km
    LET $dlat = math::rad($lat2 - $lat1);
    LET $dlon = math::rad($lon2 - $lon1);
    LET $a = math::sin($dlat / 2) * math::sin($dlat / 2) +
             math::cos(math::rad($lat1)) * math::cos(math::rad($lat2)) *
             math::sin($dlon / 2) * math::sin($dlon / 2);
    LET $c = 2 * math::atan2(math::sqrt($a), math::sqrt(1 - $a));
    RETURN $R * $c;
};

-- Calculate carbon emissions for a shipment segment
DEFINE FUNCTION fn::calculate_carbon($distance_km: decimal, $weight_kg: decimal, $carbon_factor: decimal) {
    LET $tonnes = $weight_kg / 1000.0;
    RETURN $distance_km * $tonnes * $carbon_factor;
};

-- Calculate weighted route score
DEFINE FUNCTION fn::route_score($cost: decimal, $carbon: decimal, $time: decimal, $labor: decimal, $weights: object) {
    LET $cost_w = $weights.cost OR 0.4;
    LET $carbon_w = $weights.carbon OR 0.2;
    LET $time_w = $weights.time OR 0.3;
    LET $labor_w = $weights.labor OR 0.1;
    RETURN $cost_w * (1 - $cost / 100000) +
           $carbon_w * (1 - $carbon / 10000) +
           $time_w * (1 - $time / 1000) +
           $labor_w * $labor;
};

-- =============================================================================
-- EVENTS: AUDIT TRAIL
-- =============================================================================

-- Log all shipment status changes
DEFINE EVENT shipment_status_change ON TABLE shipment WHEN $before.status != $after.status THEN {
    CREATE audit_log SET
        table = "shipment",
        record_id = $after.id,
        action = "status_change",
        old_value = $before.status,
        new_value = $after.status,
        timestamp = time::now();
};

-- Log all route status changes
DEFINE EVENT route_status_change ON TABLE route WHEN $before.status != $after.status THEN {
    CREATE audit_log SET
        table = "route",
        record_id = $after.id,
        action = "status_change",
        old_value = $before.status,
        new_value = $after.status,
        timestamp = time::now();
};

-- Audit log table
DEFINE TABLE audit_log SCHEMAFULL;
DEFINE FIELD table ON audit_log TYPE string;
DEFINE FIELD record_id ON audit_log TYPE any;
DEFINE FIELD action ON audit_log TYPE string;
DEFINE FIELD old_value ON audit_log TYPE any;
DEFINE FIELD new_value ON audit_log TYPE any;
DEFINE FIELD user_id ON audit_log TYPE option<string>;
DEFINE FIELD timestamp ON audit_log TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_audit_table ON audit_log FIELDS table;
DEFINE INDEX idx_audit_time ON audit_log FIELDS timestamp;

-- VEDS SurrealDB Schema
-- Transport Network, Shipments, Routes, Tracking
-- Run with: surreal import --conn http://localhost:8000 --ns veds --db production config/surrealdb-schema.surql

-- =============================================================================
-- NAMESPACE AND DATABASE
-- =============================================================================

USE NS veds;
USE DB production;

-- =============================================================================
-- REFERENCE DATA
-- =============================================================================

-- Countries with labor/regulatory data
DEFINE TABLE country SCHEMAFULL;
DEFINE FIELD code ON country TYPE string ASSERT $value = /^[A-Z]{2}$/;
DEFINE FIELD name ON country TYPE string;
DEFINE FIELD min_wage_cents_hourly ON country TYPE int;
DEFINE FIELD max_weekly_hours ON country TYPE int DEFAULT 48;
DEFINE FIELD currency ON country TYPE string DEFAULT "USD";
DEFINE FIELD region ON country TYPE string;  -- EU, APAC, NA, etc.
DEFINE INDEX idx_country_code ON country FIELDS code UNIQUE;

-- Ports/Terminals
DEFINE TABLE port SCHEMAFULL;
DEFINE FIELD unlocode ON port TYPE string;  -- UN/LOCODE e.g., NLRTM
DEFINE FIELD name ON port TYPE string;
DEFINE FIELD country ON port TYPE record<country>;
DEFINE FIELD location ON port TYPE geometry<point>;
DEFINE FIELD timezone ON port TYPE string;
DEFINE FIELD port_type ON port TYPE string
    ASSERT $value IN ["SEAPORT", "RAILYARD", "AIRPORT", "INLAND_PORT", "MULTIMODAL"];
DEFINE FIELD modes ON port TYPE array<string> DEFAULT [];
DEFINE FIELD capacity_teu ON port TYPE option<int>;
DEFINE FIELD avg_dwell_hours ON port TYPE float DEFAULT 24.0;
DEFINE INDEX idx_port_unlocode ON port FIELDS unlocode UNIQUE;
DEFINE INDEX idx_port_location ON port FIELDS location;
DEFINE INDEX idx_port_type ON port FIELDS port_type;

-- Cargo types
DEFINE TABLE cargo_type SCHEMAFULL;
DEFINE FIELD code ON cargo_type TYPE string;
DEFINE FIELD name ON cargo_type TYPE string;
DEFINE FIELD hazmat_class ON cargo_type TYPE option<string>;
DEFINE FIELD temp_controlled ON cargo_type TYPE bool DEFAULT false;
DEFINE FIELD temp_min_c ON cargo_type TYPE option<float>;
DEFINE FIELD temp_max_c ON cargo_type TYPE option<float>;
DEFINE FIELD stackable ON cargo_type TYPE bool DEFAULT true;
DEFINE FIELD requires_customs ON cargo_type TYPE bool DEFAULT true;
DEFINE INDEX idx_cargo_code ON cargo_type FIELDS code UNIQUE;

-- =============================================================================
-- CARRIERS
-- =============================================================================

DEFINE TABLE carrier SCHEMAFULL;
DEFINE FIELD code ON carrier TYPE string;
DEFINE FIELD name ON carrier TYPE string;
DEFINE FIELD carrier_type ON carrier TYPE string
    ASSERT $value IN ["SHIPPING_LINE", "RAIL_OPERATOR", "TRUCKING", "AIRLINE", "MULTIMODAL"];
DEFINE FIELD country ON carrier TYPE record<country>;
DEFINE FIELD safety_rating ON carrier TYPE int ASSERT $value >= 1 AND $value <= 5;
DEFINE FIELD unionized ON carrier TYPE bool DEFAULT false;
DEFINE FIELD avg_wage_cents_hourly ON carrier TYPE int;
DEFINE FIELD avg_weekly_hours ON carrier TYPE float;
DEFINE FIELD sanctioned ON carrier TYPE bool DEFAULT false;
DEFINE FIELD active ON carrier TYPE bool DEFAULT true;
DEFINE FIELD api_endpoint ON carrier TYPE option<string>;
DEFINE FIELD created_at ON carrier TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON carrier TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_carrier_code ON carrier FIELDS code UNIQUE;
DEFINE INDEX idx_carrier_type ON carrier FIELDS carrier_type;
DEFINE INDEX idx_carrier_sanctioned ON carrier FIELDS sanctioned;

-- =============================================================================
-- TRANSPORT NETWORK (GRAPH)
-- =============================================================================

-- Transport nodes (hubs, terminals)
DEFINE TABLE transport_node SCHEMAFULL;
DEFINE FIELD code ON transport_node TYPE string;
DEFINE FIELD port ON transport_node TYPE record<port>;
DEFINE FIELD node_type ON transport_node TYPE string
    ASSERT $value IN ["HUB", "TERMINAL", "WAYPOINT", "BORDER_CROSSING"];
DEFINE FIELD modes ON transport_node TYPE array<string>;  -- ["MARITIME", "RAIL", "ROAD"]
DEFINE FIELD active ON transport_node TYPE bool DEFAULT true;
DEFINE INDEX idx_node_code ON transport_node FIELDS code UNIQUE;
DEFINE INDEX idx_node_type ON transport_node FIELDS node_type;

-- Transport edges (routes between nodes)
DEFINE TABLE transport_edge SCHEMAFULL;
DEFINE FIELD code ON transport_edge TYPE string;
DEFINE FIELD from_node ON transport_edge TYPE record<transport_node>;
DEFINE FIELD to_node ON transport_edge TYPE record<transport_node>;
DEFINE FIELD carrier ON transport_edge TYPE record<carrier>;
DEFINE FIELD mode ON transport_edge TYPE string
    ASSERT $value IN ["MARITIME", "RAIL", "ROAD", "AIR"];
DEFINE FIELD distance_km ON transport_edge TYPE float;
DEFINE FIELD base_cost_usd ON transport_edge TYPE decimal;
DEFINE FIELD cost_per_kg_usd ON transport_edge TYPE decimal DEFAULT 0.0;
DEFINE FIELD cost_per_m3_usd ON transport_edge TYPE decimal DEFAULT 0.0;
DEFINE FIELD transit_hours ON transport_edge TYPE float;
DEFINE FIELD carbon_kg_per_tonne_km ON transport_edge TYPE float;
DEFINE FIELD frequency ON transport_edge TYPE string DEFAULT "DAILY";  -- DAILY, WEEKLY, etc.
DEFINE FIELD schedule ON transport_edge TYPE option<object>;  -- JSON schedule
DEFINE FIELD active ON transport_edge TYPE bool DEFAULT true;
DEFINE FIELD valid_from ON transport_edge TYPE datetime DEFAULT time::now();
DEFINE FIELD valid_to ON transport_edge TYPE option<datetime>;
DEFINE INDEX idx_edge_code ON transport_edge FIELDS code UNIQUE;
DEFINE INDEX idx_edge_mode ON transport_edge FIELDS mode;
DEFINE INDEX idx_edge_from ON transport_edge FIELDS from_node;
DEFINE INDEX idx_edge_to ON transport_edge FIELDS to_node;
DEFINE INDEX idx_edge_carrier ON transport_edge FIELDS carrier;

-- Edge for graph traversal (SurrealDB graph relations)
DEFINE TABLE connects SCHEMAFULL;
DEFINE FIELD in ON connects TYPE record<transport_node>;
DEFINE FIELD out ON connects TYPE record<transport_node>;
DEFINE FIELD edge ON connects TYPE record<transport_edge>;
DEFINE FIELD mode ON connects TYPE string;
DEFINE FIELD weight ON connects TYPE float;  -- For pathfinding (cost or time)

-- =============================================================================
-- SHIPMENTS
-- =============================================================================

DEFINE TABLE shipper SCHEMAFULL;
DEFINE FIELD code ON shipper TYPE string;
DEFINE FIELD name ON shipper TYPE string;
DEFINE FIELD country ON shipper TYPE record<country>;
DEFINE FIELD contact_email ON shipper TYPE string;
DEFINE FIELD api_key_hash ON shipper TYPE option<string>;
DEFINE FIELD active ON shipper TYPE bool DEFAULT true;
DEFINE FIELD created_at ON shipper TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_shipper_code ON shipper FIELDS code UNIQUE;

DEFINE TABLE shipment SCHEMAFULL;
DEFINE FIELD reference ON shipment TYPE string;
DEFINE FIELD shipper ON shipment TYPE record<shipper>;
DEFINE FIELD origin ON shipment TYPE record<port>;
DEFINE FIELD destination ON shipment TYPE record<port>;
DEFINE FIELD cargo_type ON shipment TYPE record<cargo_type>;
DEFINE FIELD weight_kg ON shipment TYPE float;
DEFINE FIELD volume_m3 ON shipment TYPE float;
DEFINE FIELD value_usd ON shipment TYPE option<decimal>;
DEFINE FIELD container_count ON shipment TYPE option<int>;
DEFINE FIELD pickup_after ON shipment TYPE datetime;
DEFINE FIELD deliver_by ON shipment TYPE datetime;
DEFINE FIELD priority ON shipment TYPE string DEFAULT "NORMAL"
    ASSERT $value IN ["LOW", "NORMAL", "HIGH", "URGENT"];
DEFINE FIELD status ON shipment TYPE string DEFAULT "DRAFT"
    ASSERT $value IN ["DRAFT", "OPTIMIZING", "ROUTED", "BOOKED", "IN_TRANSIT",
                      "DELIVERED", "CANCELLED", "EXCEPTION"];
DEFINE FIELD constraints ON shipment TYPE option<object>;  -- User-specified constraints JSON
DEFINE FIELD created_at ON shipment TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON shipment TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_shipment_ref ON shipment FIELDS reference UNIQUE;
DEFINE INDEX idx_shipment_status ON shipment FIELDS status;
DEFINE INDEX idx_shipment_shipper ON shipment FIELDS shipper;
DEFINE INDEX idx_shipment_dates ON shipment FIELDS pickup_after, deliver_by;

-- =============================================================================
-- ROUTES
-- =============================================================================

DEFINE TABLE route SCHEMAFULL;
DEFINE FIELD shipment ON route TYPE record<shipment>;
DEFINE FIELD status ON route TYPE string DEFAULT "CANDIDATE"
    ASSERT $value IN ["CANDIDATE", "SELECTED", "ACTIVE", "COMPLETED", "CANCELLED"];
DEFINE FIELD total_cost_usd ON route TYPE decimal;
DEFINE FIELD total_time_hours ON route TYPE float;
DEFINE FIELD total_carbon_kg ON route TYPE float;
DEFINE FIELD total_distance_km ON route TYPE float;
DEFINE FIELD labor_score ON route TYPE float;  -- 0.0 - 1.0
DEFINE FIELD pareto_rank ON route TYPE int DEFAULT 0;
DEFINE FIELD pareto_optimal ON route TYPE bool DEFAULT false;
DEFINE FIELD verified ON route TYPE bool DEFAULT false;
DEFINE FIELD proof_cert_id ON route TYPE option<string>;  -- Reference to XTDB proof
DEFINE FIELD decision_id ON route TYPE option<string>;    -- Reference to XTDB decision
DEFINE FIELD created_at ON route TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_route_shipment ON route FIELDS shipment;
DEFINE INDEX idx_route_status ON route FIELDS status;
DEFINE INDEX idx_route_pareto ON route FIELDS pareto_optimal;

DEFINE TABLE segment SCHEMAFULL;
DEFINE FIELD route ON segment TYPE record<route>;
DEFINE FIELD edge ON segment TYPE record<transport_edge>;
DEFINE FIELD sequence ON segment TYPE int;
DEFINE FIELD departure_time ON segment TYPE datetime;
DEFINE FIELD arrival_time ON segment TYPE datetime;
DEFINE FIELD cost_usd ON segment TYPE decimal;
DEFINE FIELD carbon_kg ON segment TYPE float;
DEFINE FIELD carrier_wage_cents ON segment TYPE int;  -- Actual wage on this segment
DEFINE FIELD status ON segment TYPE string DEFAULT "PENDING"
    ASSERT $value IN ["PENDING", "BOOKED", "IN_TRANSIT", "COMPLETED", "DELAYED", "CANCELLED"];
DEFINE FIELD booking_reference ON segment TYPE option<string>;
DEFINE INDEX idx_segment_route ON segment FIELDS route;
DEFINE INDEX idx_segment_sequence ON segment FIELDS route, sequence;

-- =============================================================================
-- TRACKING
-- =============================================================================

DEFINE TABLE tracking_event SCHEMAFULL;
DEFINE FIELD shipment ON tracking_event TYPE record<shipment>;
DEFINE FIELD segment ON tracking_event TYPE option<record<segment>>;
DEFINE FIELD event_type ON tracking_event TYPE string
    ASSERT $value IN ["CREATED", "BOOKED", "PICKUP", "DEPARTURE", "ARRIVAL",
                      "POSITION", "DELAY", "ALERT", "DELIVERED", "EXCEPTION"];
DEFINE FIELD timestamp ON tracking_event TYPE datetime DEFAULT time::now();
DEFINE FIELD location ON tracking_event TYPE option<geometry<point>>;
DEFINE FIELD details ON tracking_event TYPE option<object>;
DEFINE FIELD source ON tracking_event TYPE string DEFAULT "SYSTEM";  -- SYSTEM, CARRIER, GPS, MANUAL
DEFINE INDEX idx_tracking_shipment ON tracking_event FIELDS shipment;
DEFINE INDEX idx_tracking_time ON tracking_event FIELDS timestamp;
DEFINE INDEX idx_tracking_type ON tracking_event FIELDS event_type;

-- =============================================================================
-- RATES (Time-varying pricing)
-- =============================================================================

DEFINE TABLE rate SCHEMAFULL;
DEFINE FIELD edge ON rate TYPE record<transport_edge>;
DEFINE FIELD valid_from ON rate TYPE datetime;
DEFINE FIELD valid_to ON rate TYPE datetime;
DEFINE FIELD base_cost_usd ON rate TYPE decimal;
DEFINE FIELD fuel_surcharge_pct ON rate TYPE float DEFAULT 0.0;
DEFINE FIELD peak_multiplier ON rate TYPE float DEFAULT 1.0;
DEFINE FIELD currency ON rate TYPE string DEFAULT "USD";
DEFINE FIELD source ON rate TYPE string DEFAULT "MANUAL";  -- MANUAL, API, ESTIMATE
DEFINE FIELD created_at ON rate TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_rate_edge ON rate FIELDS edge;
DEFINE INDEX idx_rate_validity ON rate FIELDS valid_from, valid_to;

-- =============================================================================
-- FUNCTIONS
-- =============================================================================

-- Calculate total route cost
DEFINE FUNCTION fn::route_cost($route_id: record<route>) {
    LET $segments = SELECT cost_usd FROM segment WHERE route = $route_id;
    RETURN math::sum($segments.cost_usd);
};

-- Calculate total route carbon
DEFINE FUNCTION fn::route_carbon($route_id: record<route>) {
    LET $segments = SELECT carbon_kg FROM segment WHERE route = $route_id;
    RETURN math::sum($segments.carbon_kg);
};

-- Find routes between two ports
DEFINE FUNCTION fn::find_routes($origin: record<port>, $dest: record<port>, $max_hops: int) {
    LET $origin_node = SELECT id FROM transport_node WHERE port = $origin LIMIT 1;
    LET $dest_node = SELECT id FROM transport_node WHERE port = $dest LIMIT 1;

    RETURN SELECT
        id,
        ->connects[$max_hops]->transport_node AS path
    FROM $origin_node[0].id
    WHERE path.port = $dest;
};

-- =============================================================================
-- EVENTS (for triggers/subscriptions)
-- =============================================================================

-- Live query support for real-time updates
DEFINE TABLE live_shipment_updates AS
    SELECT
        id,
        reference,
        status,
        updated_at
    FROM shipment
    WHERE status IN ["IN_TRANSIT", "OPTIMIZING", "BOOKED"];

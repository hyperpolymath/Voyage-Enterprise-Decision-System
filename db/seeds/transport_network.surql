-- SPDX-License-Identifier: MIT OR AGPL-3.0
-- VEDS Seed Data: Transport Network
-- Sample data for MVP testing

USE NS veds;
USE DB production;

-- =============================================================================
-- COUNTRIES
-- =============================================================================

CREATE country:cn SET
    code = "CN",
    name = "China",
    region = "Asia-Pacific",
    min_wage_cents_hourly = 250,
    carbon_tax_per_tonne = 0,
    timezone = "Asia/Shanghai";

CREATE country:nl SET
    code = "NL",
    name = "Netherlands",
    region = "Europe",
    min_wage_cents_hourly = 1200,
    carbon_tax_per_tonne = 50.0,
    timezone = "Europe/Amsterdam";

CREATE country:de SET
    code = "DE",
    name = "Germany",
    region = "Europe",
    min_wage_cents_hourly = 1200,
    carbon_tax_per_tonne = 45.0,
    timezone = "Europe/Berlin";

CREATE country:us SET
    code = "US",
    name = "United States",
    region = "North America",
    min_wage_cents_hourly = 725,
    carbon_tax_per_tonne = 0,
    timezone = "America/New_York";

CREATE country:sg SET
    code = "SG",
    name = "Singapore",
    region = "Asia-Pacific",
    min_wage_cents_hourly = 0,
    carbon_tax_per_tonne = 5.0,
    timezone = "Asia/Singapore";

-- =============================================================================
-- PORTS
-- =============================================================================

CREATE port:cnsha SET
    unlocode = "CNSHA",
    name = "Shanghai",
    country = country:cn,
    location = { type: "Point", coordinates: [121.4737, 31.2304] },
    timezone = "Asia/Shanghai",
    port_type = "multimodal",
    avg_dwell_hours = 24.0,
    congestion_factor = 1.2,
    active = true;

CREATE port:nlrtm SET
    unlocode = "NLRTM",
    name = "Rotterdam",
    country = country:nl,
    location = { type: "Point", coordinates: [4.4792, 51.9225] },
    timezone = "Europe/Amsterdam",
    port_type = "multimodal",
    avg_dwell_hours = 18.0,
    congestion_factor = 1.0,
    active = true;

CREATE port:deham SET
    unlocode = "DEHAM",
    name = "Hamburg",
    country = country:de,
    location = { type: "Point", coordinates: [9.9937, 53.5511] },
    timezone = "Europe/Berlin",
    port_type = "multimodal",
    avg_dwell_hours = 20.0,
    congestion_factor = 1.1,
    active = true;

CREATE port:uslax SET
    unlocode = "USLAX",
    name = "Los Angeles",
    country = country:us,
    location = { type: "Point", coordinates: [-118.2437, 33.7490] },
    timezone = "America/Los_Angeles",
    port_type = "multimodal",
    avg_dwell_hours = 36.0,
    congestion_factor = 1.4,
    active = true;

CREATE port:usnyc SET
    unlocode = "USNYC",
    name = "New York/New Jersey",
    country = country:us,
    location = { type: "Point", coordinates: [-74.0060, 40.7128] },
    timezone = "America/New_York",
    port_type = "multimodal",
    avg_dwell_hours = 30.0,
    congestion_factor = 1.2,
    active = true;

CREATE port:sgsin SET
    unlocode = "SGSIN",
    name = "Singapore",
    country = country:sg,
    location = { type: "Point", coordinates: [103.8198, 1.3521] },
    timezone = "Asia/Singapore",
    port_type = "multimodal",
    avg_dwell_hours = 12.0,
    congestion_factor = 0.9,
    active = true;

-- =============================================================================
-- CARRIERS
-- =============================================================================

CREATE carrier:maeu SET
    code = "MAEU",
    name = "Maersk Line",
    carrier_type = "shipping",
    country = country:nl,
    avg_wage_cents_hourly = 2500,
    safety_rating = 4,
    unionized = true,
    sanctioned = false,
    sustainability_score = 0.75,
    active = true;

CREATE carrier:mscu SET
    code = "MSCU",
    name = "MSC",
    carrier_type = "shipping",
    country = country:sg,
    avg_wage_cents_hourly = 2200,
    safety_rating = 4,
    unionized = false,
    sanctioned = false,
    sustainability_score = 0.65,
    active = true;

CREATE carrier:cmau SET
    code = "CMAU",
    name = "CMA CGM",
    carrier_type = "shipping",
    country = country:nl,
    avg_wage_cents_hourly = 2400,
    safety_rating = 4,
    unionized = true,
    sanctioned = false,
    sustainability_score = 0.70,
    active = true;

CREATE carrier:dbrail SET
    code = "DBRAIL",
    name = "DB Cargo",
    carrier_type = "rail",
    country = country:de,
    avg_wage_cents_hourly = 2800,
    safety_rating = 5,
    unionized = true,
    sanctioned = false,
    sustainability_score = 0.85,
    active = true;

CREATE carrier:ups SET
    code = "UPS",
    name = "UPS Freight",
    carrier_type = "trucking",
    country = country:us,
    avg_wage_cents_hourly = 2200,
    safety_rating = 4,
    unionized = true,
    sanctioned = false,
    sustainability_score = 0.60,
    active = true;

-- =============================================================================
-- TRANSPORT NODES
-- =============================================================================

CREATE transport_node:cnsha SET
    code = "CNSHA",
    port = port:cnsha,
    node_type = "hub",
    modes = ["MARITIME", "RAIL", "ROAD"],
    capacity_teu_day = 50000,
    handling_cost_usd = 150.0,
    active = true;

CREATE transport_node:nlrtm SET
    code = "NLRTM",
    port = port:nlrtm,
    node_type = "hub",
    modes = ["MARITIME", "RAIL", "ROAD"],
    capacity_teu_day = 40000,
    handling_cost_usd = 200.0,
    active = true;

CREATE transport_node:deham SET
    code = "DEHAM",
    port = port:deham,
    node_type = "hub",
    modes = ["MARITIME", "RAIL", "ROAD"],
    capacity_teu_day = 35000,
    handling_cost_usd = 180.0,
    active = true;

CREATE transport_node:uslax SET
    code = "USLAX",
    port = port:uslax,
    node_type = "hub",
    modes = ["MARITIME", "RAIL", "ROAD"],
    capacity_teu_day = 30000,
    handling_cost_usd = 250.0,
    active = true;

CREATE transport_node:usnyc SET
    code = "USNYC",
    port = port:usnyc,
    node_type = "hub",
    modes = ["MARITIME", "RAIL", "ROAD"],
    capacity_teu_day = 25000,
    handling_cost_usd = 280.0,
    active = true;

CREATE transport_node:sgsin SET
    code = "SGSIN",
    port = port:sgsin,
    node_type = "hub",
    modes = ["MARITIME", "ROAD", "AIR"],
    capacity_teu_day = 45000,
    handling_cost_usd = 120.0,
    active = true;

-- =============================================================================
-- TRANSPORT EDGES (Maritime Routes)
-- =============================================================================

-- Shanghai to Rotterdam (via Suez)
CREATE transport_edge:cnsha_nlrtm_m SET
    code = "CNSHA-NLRTM-M",
    from_node = transport_node:cnsha,
    to_node = transport_node:nlrtm,
    carrier = carrier:maeu,
    mode = "MARITIME",
    distance_km = 19500.0,
    base_cost_usd = 2500.0,
    cost_per_kg_usd = 0.012,
    transit_hours = 672.0,
    carbon_kg_per_tonne_km = 0.015,
    frequency_per_week = 3,
    capacity_kg = 20000000,
    reliability_score = 0.92,
    active = true;

-- Shanghai to Singapore
CREATE transport_edge:cnsha_sgsin_m SET
    code = "CNSHA-SGSIN-M",
    from_node = transport_node:cnsha,
    to_node = transport_node:sgsin,
    carrier = carrier:mscu,
    mode = "MARITIME",
    distance_km = 3800.0,
    base_cost_usd = 800.0,
    cost_per_kg_usd = 0.008,
    transit_hours = 120.0,
    carbon_kg_per_tonne_km = 0.018,
    frequency_per_week = 7,
    capacity_kg = 15000000,
    reliability_score = 0.95,
    active = true;

-- Singapore to Rotterdam
CREATE transport_edge:sgsin_nlrtm_m SET
    code = "SGSIN-NLRTM-M",
    from_node = transport_node:sgsin,
    to_node = transport_node:nlrtm,
    carrier = carrier:cmau,
    mode = "MARITIME",
    distance_km = 15200.0,
    base_cost_usd = 2000.0,
    cost_per_kg_usd = 0.011,
    transit_hours = 480.0,
    carbon_kg_per_tonne_km = 0.014,
    frequency_per_week = 5,
    capacity_kg = 18000000,
    reliability_score = 0.93,
    active = true;

-- Shanghai to Los Angeles
CREATE transport_edge:cnsha_uslax_m SET
    code = "CNSHA-USLAX-M",
    from_node = transport_node:cnsha,
    to_node = transport_node:uslax,
    carrier = carrier:maeu,
    mode = "MARITIME",
    distance_km = 11500.0,
    base_cost_usd = 2200.0,
    cost_per_kg_usd = 0.015,
    transit_hours = 336.0,
    carbon_kg_per_tonne_km = 0.016,
    frequency_per_week = 4,
    capacity_kg = 22000000,
    reliability_score = 0.88,
    active = true;

-- Rotterdam to Hamburg (Rail)
CREATE transport_edge:nlrtm_deham_r SET
    code = "NLRTM-DEHAM-R",
    from_node = transport_node:nlrtm,
    to_node = transport_node:deham,
    carrier = carrier:dbrail,
    mode = "RAIL",
    distance_km = 490.0,
    base_cost_usd = 300.0,
    cost_per_kg_usd = 0.005,
    transit_hours = 8.0,
    carbon_kg_per_tonne_km = 0.022,
    frequency_per_week = 14,
    capacity_kg = 2000000,
    reliability_score = 0.97,
    active = true;

-- Los Angeles to New York (Rail)
CREATE transport_edge:uslax_usnyc_r SET
    code = "USLAX-USNYC-R",
    from_node = transport_node:uslax,
    to_node = transport_node:usnyc,
    carrier = carrier:ups,
    mode = "RAIL",
    distance_km = 4500.0,
    base_cost_usd = 1500.0,
    cost_per_kg_usd = 0.008,
    transit_hours = 96.0,
    carbon_kg_per_tonne_km = 0.025,
    frequency_per_week = 7,
    capacity_kg = 3000000,
    reliability_score = 0.90,
    active = true;

-- Hamburg to Rotterdam (Road)
CREATE transport_edge:deham_nlrtm_t SET
    code = "DEHAM-NLRTM-T",
    from_node = transport_node:deham,
    to_node = transport_node:nlrtm,
    carrier = carrier:ups,
    mode = "ROAD",
    distance_km = 460.0,
    base_cost_usd = 400.0,
    cost_per_kg_usd = 0.015,
    transit_hours = 6.0,
    carbon_kg_per_tonne_km = 0.085,
    frequency_per_week = 21,
    capacity_kg = 25000,
    reliability_score = 0.94,
    active = true;

-- Rotterdam to New York (Maritime)
CREATE transport_edge:nlrtm_usnyc_m SET
    code = "NLRTM-USNYC-M",
    from_node = transport_node:nlrtm,
    to_node = transport_node:usnyc,
    carrier = carrier:maeu,
    mode = "MARITIME",
    distance_km = 5800.0,
    base_cost_usd = 1800.0,
    cost_per_kg_usd = 0.010,
    transit_hours = 192.0,
    carbon_kg_per_tonne_km = 0.016,
    frequency_per_week = 6,
    capacity_kg = 18000000,
    reliability_score = 0.91,
    active = true;

-- =============================================================================
-- GRAPH RELATIONS (for traversal)
-- =============================================================================

RELATE transport_node:cnsha->transport_node:nlrtm SET
    edge = transport_edge:cnsha_nlrtm_m,
    mode = "MARITIME",
    distance_km = 19500.0,
    transit_hours = 672.0;

RELATE transport_node:cnsha->transport_node:sgsin SET
    edge = transport_edge:cnsha_sgsin_m,
    mode = "MARITIME",
    distance_km = 3800.0,
    transit_hours = 120.0;

RELATE transport_node:sgsin->transport_node:nlrtm SET
    edge = transport_edge:sgsin_nlrtm_m,
    mode = "MARITIME",
    distance_km = 15200.0,
    transit_hours = 480.0;

RELATE transport_node:cnsha->transport_node:uslax SET
    edge = transport_edge:cnsha_uslax_m,
    mode = "MARITIME",
    distance_km = 11500.0,
    transit_hours = 336.0;

RELATE transport_node:nlrtm->transport_node:deham SET
    edge = transport_edge:nlrtm_deham_r,
    mode = "RAIL",
    distance_km = 490.0,
    transit_hours = 8.0;

RELATE transport_node:uslax->transport_node:usnyc SET
    edge = transport_edge:uslax_usnyc_r,
    mode = "RAIL",
    distance_km = 4500.0,
    transit_hours = 96.0;

RELATE transport_node:deham->transport_node:nlrtm SET
    edge = transport_edge:deham_nlrtm_t,
    mode = "ROAD",
    distance_km = 460.0,
    transit_hours = 6.0;

RELATE transport_node:nlrtm->transport_node:usnyc SET
    edge = transport_edge:nlrtm_usnyc_m,
    mode = "MARITIME",
    distance_km = 5800.0,
    transit_hours = 192.0;

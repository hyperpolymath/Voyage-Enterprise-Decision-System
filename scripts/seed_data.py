#!/usr/bin/env python3
"""
VEDS Synthetic Data Generator

Generates realistic transport network data for the Shanghai → Rotterdam → London corridor.
Seeds both SurrealDB (transport network) and Dragonfly (constraint cache).

Usage:
    python scripts/seed_data.py [--surrealdb-url URL] [--dragonfly-url URL]
"""

import argparse
import json
import random
import uuid
from datetime import datetime, timedelta
from typing import Any

import httpx
import redis

# =============================================================================
# REFERENCE DATA
# =============================================================================

COUNTRIES = {
    "CN": {"name": "China", "min_wage_cents": 350, "max_hours": 44, "region": "APAC"},
    "SG": {"name": "Singapore", "min_wage_cents": 0, "max_hours": 44, "region": "APAC"},
    "MY": {"name": "Malaysia", "min_wage_cents": 280, "max_hours": 48, "region": "APAC"},
    "EG": {"name": "Egypt", "min_wage_cents": 180, "max_hours": 48, "region": "MENA"},
    "NL": {"name": "Netherlands", "min_wage_cents": 1395, "max_hours": 40, "region": "EU"},
    "DE": {"name": "Germany", "min_wage_cents": 1260, "max_hours": 48, "region": "EU"},
    "BE": {"name": "Belgium", "min_wage_cents": 1955, "max_hours": 38, "region": "EU"},
    "FR": {"name": "France", "min_wage_cents": 1398, "max_hours": 35, "region": "EU"},
    "GB": {"name": "United Kingdom", "min_wage_cents": 1340, "max_hours": 48, "region": "EU"},
    "PL": {"name": "Poland", "min_wage_cents": 660, "max_hours": 48, "region": "EU"},
}

PORTS = [
    # China
    {"unlocode": "CNSHA", "name": "Shanghai", "country": "CN", "lat": 31.2304, "lon": 121.4737,
     "type": "SEAPORT", "modes": ["MARITIME", "RAIL", "ROAD"], "dwell_hours": 24},
    {"unlocode": "CNNGB", "name": "Ningbo", "country": "CN", "lat": 29.8683, "lon": 121.5440,
     "type": "SEAPORT", "modes": ["MARITIME", "RAIL"], "dwell_hours": 18},

    # Singapore
    {"unlocode": "SGSIN", "name": "Singapore", "country": "SG", "lat": 1.2644, "lon": 103.8200,
     "type": "SEAPORT", "modes": ["MARITIME", "ROAD"], "dwell_hours": 12},

    # Suez Canal
    {"unlocode": "EGSUZ", "name": "Port Said", "country": "EG", "lat": 31.2653, "lon": 32.3019,
     "type": "SEAPORT", "modes": ["MARITIME"], "dwell_hours": 6},

    # Europe
    {"unlocode": "NLRTM", "name": "Rotterdam", "country": "NL", "lat": 51.9225, "lon": 4.4792,
     "type": "SEAPORT", "modes": ["MARITIME", "RAIL", "ROAD"], "dwell_hours": 18},
    {"unlocode": "DEHAM", "name": "Hamburg", "country": "DE", "lat": 53.5511, "lon": 9.9937,
     "type": "SEAPORT", "modes": ["MARITIME", "RAIL", "ROAD"], "dwell_hours": 18},
    {"unlocode": "BEANR", "name": "Antwerp", "country": "BE", "lat": 51.2194, "lon": 4.4025,
     "type": "SEAPORT", "modes": ["MARITIME", "RAIL", "ROAD"], "dwell_hours": 18},

    # Inland/Rail hubs
    {"unlocode": "DEDUI", "name": "Duisburg", "country": "DE", "lat": 51.4344, "lon": 6.7623,
     "type": "RAILYARD", "modes": ["RAIL", "ROAD"], "dwell_hours": 8},
    {"unlocode": "PLWAW", "name": "Warsaw", "country": "PL", "lat": 52.2297, "lon": 21.0122,
     "type": "RAILYARD", "modes": ["RAIL", "ROAD"], "dwell_hours": 8},

    # UK
    {"unlocode": "GBFXT", "name": "Felixstowe", "country": "GB", "lat": 51.9536, "lon": 1.3511,
     "type": "SEAPORT", "modes": ["MARITIME", "RAIL", "ROAD"], "dwell_hours": 18},
    {"unlocode": "GBLHR", "name": "London Heathrow", "country": "GB", "lat": 51.4700, "lon": -0.4543,
     "type": "AIRPORT", "modes": ["AIR", "ROAD"], "dwell_hours": 4},
    {"unlocode": "GBLON", "name": "London (Distribution)", "country": "GB", "lat": 51.5074, "lon": -0.1278,
     "type": "INLAND_PORT", "modes": ["ROAD", "RAIL"], "dwell_hours": 6},
]

CARRIERS = [
    # Shipping lines
    {"code": "MAEU", "name": "Maersk", "type": "SHIPPING_LINE", "country": "NL",
     "safety": 5, "unionized": True, "wage": 2800, "hours": 42},
    {"code": "CMDU", "name": "CMA CGM", "type": "SHIPPING_LINE", "country": "FR",
     "safety": 4, "unionized": True, "wage": 2600, "hours": 40},
    {"code": "COSU", "name": "COSCO", "type": "SHIPPING_LINE", "country": "CN",
     "safety": 4, "unionized": False, "wage": 1200, "hours": 48},
    {"code": "MSCU", "name": "MSC", "type": "SHIPPING_LINE", "country": "NL",
     "safety": 4, "unionized": True, "wage": 2700, "hours": 42},

    # Rail operators
    {"code": "DBCG", "name": "DB Cargo", "type": "RAIL_OPERATOR", "country": "DE",
     "safety": 5, "unionized": True, "wage": 2400, "hours": 38},
    {"code": "SNCF", "name": "SNCF Fret", "type": "RAIL_OPERATOR", "country": "FR",
     "safety": 5, "unionized": True, "wage": 2500, "hours": 35},
    {"code": "PKPC", "name": "PKP Cargo", "type": "RAIL_OPERATOR", "country": "PL",
     "safety": 4, "unionized": True, "wage": 1400, "hours": 42},

    # Trucking
    {"code": "DFDS", "name": "DFDS Logistics", "type": "TRUCKING", "country": "NL",
     "safety": 4, "unionized": True, "wage": 2200, "hours": 45},
    {"code": "RHEL", "name": "Rhenus Logistics", "type": "TRUCKING", "country": "DE",
     "safety": 4, "unionized": True, "wage": 2100, "hours": 45},
    {"code": "EDLS", "name": "Eddie Stobart", "type": "TRUCKING", "country": "GB",
     "safety": 4, "unionized": False, "wage": 1800, "hours": 48},

    # Air cargo
    {"code": "LHCG", "name": "Lufthansa Cargo", "type": "AIRLINE", "country": "DE",
     "safety": 5, "unionized": True, "wage": 3500, "hours": 40},
]

# Carbon emission factors (kg CO2 per tonne-km)
CARBON_FACTORS = {
    "MARITIME": 0.015,
    "RAIL": 0.025,
    "ROAD": 0.100,
    "AIR": 0.800,
}

# =============================================================================
# EDGE GENERATION
# =============================================================================

ROUTES = [
    # Maritime routes (Shanghai corridor)
    {"from": "CNSHA", "to": "SGSIN", "mode": "MARITIME", "km": 3800, "hours": 120, "carriers": ["MAEU", "COSU", "CMDU"]},
    {"from": "SGSIN", "to": "EGSUZ", "mode": "MARITIME", "km": 8500, "hours": 288, "carriers": ["MAEU", "COSU", "CMDU", "MSCU"]},
    {"from": "EGSUZ", "to": "NLRTM", "mode": "MARITIME", "km": 5200, "hours": 168, "carriers": ["MAEU", "CMDU", "MSCU"]},
    {"from": "EGSUZ", "to": "DEHAM", "mode": "MARITIME", "km": 5800, "hours": 192, "carriers": ["MAEU", "MSCU"]},
    {"from": "CNSHA", "to": "NLRTM", "mode": "MARITIME", "km": 19500, "hours": 672, "carriers": ["MAEU", "CMDU", "COSU"]},

    # Rail routes (Europe)
    {"from": "NLRTM", "to": "DEDUI", "mode": "RAIL", "km": 220, "hours": 6, "carriers": ["DBCG"]},
    {"from": "DEDUI", "to": "PLWAW", "mode": "RAIL", "km": 900, "hours": 18, "carriers": ["DBCG", "PKPC"]},
    {"from": "PLWAW", "to": "CNSHA", "mode": "RAIL", "km": 9000, "hours": 336, "carriers": ["PKPC"]},  # New Silk Road rail
    {"from": "DEHAM", "to": "DEDUI", "mode": "RAIL", "km": 350, "hours": 8, "carriers": ["DBCG"]},
    {"from": "NLRTM", "to": "BEANR", "mode": "RAIL", "km": 100, "hours": 3, "carriers": ["DBCG", "SNCF"]},

    # Road routes (last mile)
    {"from": "NLRTM", "to": "GBLON", "mode": "ROAD", "km": 450, "hours": 10, "carriers": ["DFDS", "RHEL"]},
    {"from": "GBFXT", "to": "GBLON", "mode": "ROAD", "km": 130, "hours": 3, "carriers": ["EDLS", "DFDS"]},
    {"from": "DEDUI", "to": "GBFXT", "mode": "ROAD", "km": 600, "hours": 14, "carriers": ["DFDS", "RHEL"]},
    {"from": "BEANR", "to": "GBFXT", "mode": "ROAD", "km": 350, "hours": 8, "carriers": ["DFDS"]},

    # Air routes
    {"from": "CNSHA", "to": "GBLHR", "mode": "AIR", "km": 9200, "hours": 14, "carriers": ["LHCG"]},
    {"from": "GBLHR", "to": "GBLON", "mode": "ROAD", "km": 30, "hours": 1, "carriers": ["EDLS"]},
]


def generate_edge(route: dict, carrier_data: dict, ports_by_code: dict) -> dict:
    """Generate a transport edge with realistic costs"""
    mode = route["mode"]
    carrier = carrier_data

    # Base cost calculation (USD)
    if mode == "MARITIME":
        base_cost = route["km"] * 0.5 + random.uniform(1000, 3000)
    elif mode == "RAIL":
        base_cost = route["km"] * 0.8 + random.uniform(500, 1500)
    elif mode == "ROAD":
        base_cost = route["km"] * 1.2 + random.uniform(200, 500)
    else:  # AIR
        base_cost = route["km"] * 3.0 + random.uniform(2000, 5000)

    return {
        "code": f"{route['from']}-{route['to']}-{mode[0]}-{carrier['code']}",
        "from_node": f"transport_node:{route['from']}",
        "to_node": f"transport_node:{route['to']}",
        "carrier": f"carrier:{carrier['code']}",
        "mode": mode,
        "distance_km": route["km"],
        "base_cost_usd": round(base_cost, 2),
        "cost_per_kg_usd": round(base_cost / 10000 * 0.01, 4),
        "transit_hours": route["hours"] + random.uniform(-route["hours"]*0.1, route["hours"]*0.1),
        "carbon_kg_per_tonne_km": CARBON_FACTORS[mode],
        "frequency": "DAILY" if mode in ["ROAD", "AIR"] else "WEEKLY",
        "active": True,
    }


# =============================================================================
# DATABASE SEEDING
# =============================================================================

class SurrealDBSeeder:
    def __init__(self, url: str, user: str, password: str):
        self.url = url.rstrip("/")
        self.auth = (user, password)
        self.client = httpx.Client(timeout=30.0)

    def query(self, sql: str) -> Any:
        """Execute a SurrealQL query"""
        resp = self.client.post(
            f"{self.url}/sql",
            content=sql,
            headers={
                "Content-Type": "application/text",
                "Accept": "application/json",
                "NS": "veds",
                "DB": "production",
            },
            auth=self.auth,
        )
        resp.raise_for_status()
        return resp.json()

    def seed_countries(self):
        """Seed country reference data"""
        print("Seeding countries...")
        for code, data in COUNTRIES.items():
            sql = f"""
            CREATE country:{code} SET
                code = '{code}',
                name = '{data["name"]}',
                min_wage_cents_hourly = {data["min_wage_cents"]},
                max_weekly_hours = {data["max_hours"]},
                region = '{data["region"]}',
                currency = 'USD';
            """
            self.query(sql)
        print(f"  Created {len(COUNTRIES)} countries")

    def seed_ports(self):
        """Seed port reference data"""
        print("Seeding ports...")
        for port in PORTS:
            sql = f"""
            CREATE port:{port["unlocode"]} SET
                unlocode = '{port["unlocode"]}',
                name = '{port["name"]}',
                country = country:{port["country"]},
                location = {{ type: 'Point', coordinates: [{port["lon"]}, {port["lat"]}] }},
                timezone = 'UTC',
                port_type = '{port["type"]}',
                modes = {json.dumps(port["modes"])},
                avg_dwell_hours = {port["dwell_hours"]};
            """
            self.query(sql)
        print(f"  Created {len(PORTS)} ports")

    def seed_carriers(self):
        """Seed carrier data"""
        print("Seeding carriers...")
        for carrier in CARRIERS:
            sql = f"""
            CREATE carrier:{carrier["code"]} SET
                code = '{carrier["code"]}',
                name = '{carrier["name"]}',
                carrier_type = '{carrier["type"]}',
                country = country:{carrier["country"]},
                safety_rating = {carrier["safety"]},
                unionized = {str(carrier["unionized"]).lower()},
                avg_wage_cents_hourly = {carrier["wage"]},
                avg_weekly_hours = {carrier["hours"]},
                sanctioned = false,
                active = true;
            """
            self.query(sql)
        print(f"  Created {len(CARRIERS)} carriers")

    def seed_transport_nodes(self):
        """Seed transport nodes"""
        print("Seeding transport nodes...")
        for port in PORTS:
            sql = f"""
            CREATE transport_node:{port["unlocode"]} SET
                code = '{port["unlocode"]}',
                port = port:{port["unlocode"]},
                node_type = 'HUB',
                modes = {json.dumps(port["modes"])},
                active = true;
            """
            self.query(sql)
        print(f"  Created {len(PORTS)} transport nodes")

    def seed_transport_edges(self):
        """Seed transport edges"""
        print("Seeding transport edges...")
        carrier_map = {c["code"]: c for c in CARRIERS}
        edge_count = 0

        for route in ROUTES:
            for carrier_code in route["carriers"]:
                edge = generate_edge(route, carrier_map[carrier_code], {})
                sql = f"""
                CREATE transport_edge SET
                    code = '{edge["code"]}',
                    from_node = transport_node:{route["from"]},
                    to_node = transport_node:{route["to"]},
                    carrier = carrier:{carrier_code},
                    mode = '{edge["mode"]}',
                    distance_km = {edge["distance_km"]},
                    base_cost_usd = {edge["base_cost_usd"]},
                    cost_per_kg_usd = {edge["cost_per_kg_usd"]},
                    transit_hours = {edge["transit_hours"]:.1f},
                    carbon_kg_per_tonne_km = {edge["carbon_kg_per_tonne_km"]},
                    frequency = '{edge["frequency"]}',
                    active = true;
                """
                self.query(sql)
                edge_count += 1

        print(f"  Created {edge_count} transport edges")

    def seed_cargo_types(self):
        """Seed cargo type reference data"""
        print("Seeding cargo types...")
        cargo_types = [
            {"code": "GEN", "name": "General Cargo", "hazmat": None, "temp": False},
            {"code": "REF", "name": "Refrigerated", "hazmat": None, "temp": True, "min_c": -25, "max_c": 5},
            {"code": "HAZ1", "name": "Explosives", "hazmat": "Class 1", "temp": False},
            {"code": "HAZ3", "name": "Flammable Liquids", "hazmat": "Class 3", "temp": False},
            {"code": "HVY", "name": "Heavy Machinery", "hazmat": None, "temp": False},
        ]
        for ct in cargo_types:
            temp_fields = ""
            if ct.get("temp"):
                temp_fields = f", temp_min_c = {ct.get('min_c', -20)}, temp_max_c = {ct.get('max_c', 10)}"
            hazmat = f"'{ct['hazmat']}'" if ct["hazmat"] else "NONE"
            sql = f"""
            CREATE cargo_type:{ct["code"]} SET
                code = '{ct["code"]}',
                name = '{ct["name"]}',
                hazmat_class = {hazmat},
                temp_controlled = {str(ct["temp"]).lower()}{temp_fields};
            """
            self.query(sql)
        print(f"  Created {len(cargo_types)} cargo types")

    def seed_all(self):
        """Seed all data"""
        self.seed_countries()
        self.seed_ports()
        self.seed_carriers()
        self.seed_cargo_types()
        self.seed_transport_nodes()
        self.seed_transport_edges()


class DragonflySeeder:
    def __init__(self, url: str, password: str = None):
        parsed = httpx.URL(url)
        self.client = redis.Redis(
            host=parsed.host or "localhost",
            port=parsed.port or 6379,
            password=password,
            decode_responses=True,
        )

    def seed_constraints(self):
        """Seed constraint lookup tables"""
        print("Seeding constraint cache in Dragonfly...")

        # Minimum wages by country
        for code, data in COUNTRIES.items():
            self.client.set(f"constraint:min_wage:{code}", data["min_wage_cents"])

        # Maximum hours by region
        regions = {}
        for code, data in COUNTRIES.items():
            region = data["region"]
            if region not in regions or data["max_hours"] < regions[region]:
                regions[region] = data["max_hours"]

        for region, hours in regions.items():
            self.client.set(f"constraint:max_hours:{region}", hours)

        # Sanctioned carriers (empty for now)
        # self.client.sadd("constraint:sanctioned:carriers", "BADCO")

        # Default carbon budget
        self.client.set("constraint:carbon_budget:default", "5000")

        print(f"  Set {len(COUNTRIES)} wage constraints")
        print(f"  Set {len(regions)} hour constraints")

    def seed_all(self):
        self.seed_constraints()


# =============================================================================
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="Seed VEDS with synthetic data")
    parser.add_argument("--surrealdb-url", default="http://localhost:8000",
                        help="SurrealDB URL")
    parser.add_argument("--surrealdb-user", default="root",
                        help="SurrealDB username")
    parser.add_argument("--surrealdb-pass", default="veds_dev_password",
                        help="SurrealDB password")
    parser.add_argument("--dragonfly-url", default="redis://localhost:6379",
                        help="Dragonfly URL")
    parser.add_argument("--dragonfly-pass", default="veds_dev_password",
                        help="Dragonfly password")

    args = parser.parse_args()

    print("=" * 60)
    print("VEDS Synthetic Data Generator")
    print("=" * 60)
    print()

    print("Seeding SurrealDB...")
    surreal = SurrealDBSeeder(args.surrealdb_url, args.surrealdb_user, args.surrealdb_pass)
    try:
        surreal.seed_all()
    except Exception as e:
        print(f"Warning: SurrealDB seeding failed: {e}")
        print("Make sure SurrealDB is running and the schema is loaded.")

    print()
    print("Seeding Dragonfly...")
    dragonfly = DragonflySeeder(args.dragonfly_url, args.dragonfly_pass)
    try:
        dragonfly.seed_all()
    except Exception as e:
        print(f"Warning: Dragonfly seeding failed: {e}")
        print("Make sure Dragonfly is running.")

    print()
    print("=" * 60)
    print("Data seeding complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()

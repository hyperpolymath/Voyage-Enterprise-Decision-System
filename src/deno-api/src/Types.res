// SPDX-License-Identifier: MIT OR AGPL-3.0
// VEDS API Types - Domain Model

// Transport modes
type transportMode = Maritime | Rail | Road | Air

let transportModeToString = mode =>
  switch mode {
  | Maritime => "MARITIME"
  | Rail => "RAIL"
  | Road => "ROAD"
  | Air => "AIR"
  }

let transportModeFromString = str =>
  switch Js.String2.toUpperCase(str) {
  | "MARITIME" => Some(Maritime)
  | "RAIL" => Some(Rail)
  | "ROAD" => Some(Road)
  | "AIR" => Some(Air)
  | _ => None
  }

// Geographic location
type location = {
  lat: float,
  lon: float,
}

// Port/Terminal
type port = {
  unlocode: string,
  name: string,
  countryCode: string,
  location: option<location>,
  portType: string,
  avgDwellHours: float,
}

// Carrier
type carrier = {
  code: string,
  name: string,
  carrierType: string,
  safetyRating: int,
  unionized: bool,
  sanctioned: bool,
}

// Transport node (graph vertex)
type transportNode = {
  code: string,
  port: port,
  nodeType: string,
  modes: array<transportMode>,
}

// Transport edge (graph edge)
type transportEdge = {
  code: string,
  fromNode: string,
  toNode: string,
  carrier: carrier,
  mode: transportMode,
  distanceKm: float,
  baseCostUsd: float,
  costPerKgUsd: float,
  transitHours: float,
  carbonPerTonneKm: float,
}

// Shipment status
type shipmentStatus =
  | Pending
  | Planned
  | InTransit
  | Delivered
  | Cancelled

let shipmentStatusToString = status =>
  switch status {
  | Pending => "pending"
  | Planned => "planned"
  | InTransit => "in_transit"
  | Delivered => "delivered"
  | Cancelled => "cancelled"
  }

let shipmentStatusFromString = str =>
  switch str {
  | "pending" => Some(Pending)
  | "planned" => Some(Planned)
  | "in_transit" => Some(InTransit)
  | "delivered" => Some(Delivered)
  | "cancelled" => Some(Cancelled)
  | _ => None
  }

// Priority levels
type priority = Low | Normal | High | Urgent

let priorityToString = p =>
  switch p {
  | Low => "low"
  | Normal => "normal"
  | High => "high"
  | Urgent => "urgent"
  }

// Shipment
type shipment = {
  id: string,
  externalId: option<string>,
  customerId: string,
  origin: string,
  destination: string,
  weightKg: float,
  volumeCbm: option<float>,
  commodityCode: string,
  commodityDesc: string,
  hazmatClass: option<string>,
  temperatureControlled: bool,
  earliestPickup: string,
  latestDelivery: string,
  priority: priority,
  status: shipmentStatus,
  maxCostUsd: option<float>,
  maxCarbonKg: option<float>,
  createdAt: string,
  updatedAt: string,
}

// Route segment
type routeSegment = {
  segmentId: string,
  sequence: int,
  fromNode: string,
  toNode: string,
  mode: transportMode,
  carrierCode: string,
  distanceKm: float,
  costUsd: float,
  transitHours: float,
  carbonKg: float,
  carrierWageCents: int,
  laborScore: float,
  departureTime: string,
  arrivalTime: string,
}

// Route status
type routeStatus = Draft | Proposed | Accepted | Executing | Completed | Failed

let routeStatusToString = status =>
  switch status {
  | Draft => "draft"
  | Proposed => "proposed"
  | Accepted => "accepted"
  | Executing => "executing"
  | Completed => "completed"
  | Failed => "failed"
  }

// Constraint result
type constraintResult = {
  constraintId: string,
  constraintType: string,
  passed: bool,
  isHard: bool,
  score: float,
  message: string,
}

// Route
type route = {
  routeId: string,
  shipmentId: string,
  status: routeStatus,
  segments: array<routeSegment>,
  totalCostUsd: float,
  totalCarbonKg: float,
  totalTransitHours: float,
  totalDistanceKm: float,
  laborScore: float,
  constraintScore: float,
  paretoOptimal: bool,
  paretoRank: int,
  weightedScore: float,
  constraintResults: array<constraintResult>,
  departureTime: option<string>,
  arrivalTime: option<string>,
}

// API Request/Response types
type optimizeRequest = {
  shipmentId: string,
  originPort: string,
  destinationPort: string,
  weightKg: float,
  volumeM3: float,
  pickupAfter: string,
  deliverBy: string,
  maxCostUsd: option<float>,
  maxCarbonKg: option<float>,
  minLaborScore: option<float>,
  allowedModes: array<string>,
  excludedCarriers: array<string>,
  maxRoutes: int,
  maxSegments: int,
  costWeight: float,
  timeWeight: float,
  carbonWeight: float,
  laborWeight: float,
}

type optimizeResponse = {
  success: bool,
  errorMessage: option<string>,
  routes: array<route>,
  optimizationTimeMs: int,
  candidatesEvaluated: int,
}

// Health check response
type healthResponse = {
  status: string,
  version: string,
  timestamp: string,
  services: Js.Dict.t<string>,
}

// Error response
type errorResponse = {
  error: string,
  message: string,
  statusCode: int,
}

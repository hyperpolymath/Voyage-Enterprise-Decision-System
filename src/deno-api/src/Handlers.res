// SPDX-License-Identifier: MIT OR AGPL-3.0
// VEDS API Handlers - Request handling logic

open Types

// JSON encoding helpers
module Encode = {
  let string = Js.Json.string
  let int = n => Js.Json.number(Js.Int.toFloat(n))
  let float = Js.Json.number
  let bool = Js.Json.boolean
  let nullable = (encoder, opt) =>
    switch opt {
    | Some(v) => encoder(v)
    | None => Js.Json.null
    }
  let array = (encoder, arr) => Js.Json.array(Js.Array2.map(arr, encoder))
  let dict = Js.Json.object_

  let shipmentStatus = status => string(shipmentStatusToString(status))
  let priority = p => string(priorityToString(p))
  let routeStatus = status => string(routeStatusToString(status))
  let transportMode = mode => string(transportModeToString(mode))

  let constraintResult = (cr: constraintResult) => {
    let obj = Js.Dict.empty()
    Js.Dict.set(obj, "constraintId", string(cr.constraintId))
    Js.Dict.set(obj, "constraintType", string(cr.constraintType))
    Js.Dict.set(obj, "passed", bool(cr.passed))
    Js.Dict.set(obj, "isHard", bool(cr.isHard))
    Js.Dict.set(obj, "score", float(cr.score))
    Js.Dict.set(obj, "message", string(cr.message))
    dict(obj)
  }

  let routeSegment = (seg: routeSegment) => {
    let obj = Js.Dict.empty()
    Js.Dict.set(obj, "segmentId", string(seg.segmentId))
    Js.Dict.set(obj, "sequence", int(seg.sequence))
    Js.Dict.set(obj, "fromNode", string(seg.fromNode))
    Js.Dict.set(obj, "toNode", string(seg.toNode))
    Js.Dict.set(obj, "mode", transportMode(seg.mode))
    Js.Dict.set(obj, "carrierCode", string(seg.carrierCode))
    Js.Dict.set(obj, "distanceKm", float(seg.distanceKm))
    Js.Dict.set(obj, "costUsd", float(seg.costUsd))
    Js.Dict.set(obj, "transitHours", float(seg.transitHours))
    Js.Dict.set(obj, "carbonKg", float(seg.carbonKg))
    Js.Dict.set(obj, "carrierWageCents", int(seg.carrierWageCents))
    Js.Dict.set(obj, "laborScore", float(seg.laborScore))
    Js.Dict.set(obj, "departureTime", string(seg.departureTime))
    Js.Dict.set(obj, "arrivalTime", string(seg.arrivalTime))
    dict(obj)
  }

  let route = (r: route) => {
    let obj = Js.Dict.empty()
    Js.Dict.set(obj, "routeId", string(r.routeId))
    Js.Dict.set(obj, "shipmentId", string(r.shipmentId))
    Js.Dict.set(obj, "status", routeStatus(r.status))
    Js.Dict.set(obj, "segments", array(routeSegment, r.segments))
    Js.Dict.set(obj, "totalCostUsd", float(r.totalCostUsd))
    Js.Dict.set(obj, "totalCarbonKg", float(r.totalCarbonKg))
    Js.Dict.set(obj, "totalTransitHours", float(r.totalTransitHours))
    Js.Dict.set(obj, "totalDistanceKm", float(r.totalDistanceKm))
    Js.Dict.set(obj, "laborScore", float(r.laborScore))
    Js.Dict.set(obj, "constraintScore", float(r.constraintScore))
    Js.Dict.set(obj, "paretoOptimal", bool(r.paretoOptimal))
    Js.Dict.set(obj, "paretoRank", int(r.paretoRank))
    Js.Dict.set(obj, "weightedScore", float(r.weightedScore))
    Js.Dict.set(obj, "constraintResults", array(constraintResult, r.constraintResults))
    Js.Dict.set(obj, "departureTime", nullable(string, r.departureTime))
    Js.Dict.set(obj, "arrivalTime", nullable(string, r.arrivalTime))
    dict(obj)
  }

  let shipment = (s: shipment) => {
    let obj = Js.Dict.empty()
    Js.Dict.set(obj, "id", string(s.id))
    Js.Dict.set(obj, "externalId", nullable(string, s.externalId))
    Js.Dict.set(obj, "customerId", string(s.customerId))
    Js.Dict.set(obj, "origin", string(s.origin))
    Js.Dict.set(obj, "destination", string(s.destination))
    Js.Dict.set(obj, "weightKg", float(s.weightKg))
    Js.Dict.set(obj, "volumeCbm", nullable(float, s.volumeCbm))
    Js.Dict.set(obj, "commodityCode", string(s.commodityCode))
    Js.Dict.set(obj, "commodityDesc", string(s.commodityDesc))
    Js.Dict.set(obj, "hazmatClass", nullable(string, s.hazmatClass))
    Js.Dict.set(obj, "temperatureControlled", bool(s.temperatureControlled))
    Js.Dict.set(obj, "earliestPickup", string(s.earliestPickup))
    Js.Dict.set(obj, "latestDelivery", string(s.latestDelivery))
    Js.Dict.set(obj, "priority", priority(s.priority))
    Js.Dict.set(obj, "status", shipmentStatus(s.status))
    Js.Dict.set(obj, "maxCostUsd", nullable(float, s.maxCostUsd))
    Js.Dict.set(obj, "maxCarbonKg", nullable(float, s.maxCarbonKg))
    Js.Dict.set(obj, "createdAt", string(s.createdAt))
    Js.Dict.set(obj, "updatedAt", string(s.updatedAt))
    dict(obj)
  }

  let healthResponse = (h: healthResponse) => {
    let obj = Js.Dict.empty()
    Js.Dict.set(obj, "status", string(h.status))
    Js.Dict.set(obj, "version", string(h.version))
    Js.Dict.set(obj, "timestamp", string(h.timestamp))
    let servicesObj =
      h.services
      ->Js.Dict.entries
      ->Js.Array2.map(((k, v)) => (k, string(v)))
      ->Js.Dict.fromArray
    Js.Dict.set(obj, "services", dict(servicesObj))
    dict(obj)
  }

  let optimizeResponse = (r: optimizeResponse) => {
    let obj = Js.Dict.empty()
    Js.Dict.set(obj, "success", bool(r.success))
    Js.Dict.set(obj, "errorMessage", nullable(string, r.errorMessage))
    Js.Dict.set(obj, "routes", array(route, r.routes))
    Js.Dict.set(obj, "optimizationTimeMs", int(r.optimizationTimeMs))
    Js.Dict.set(obj, "candidatesEvaluated", int(r.candidatesEvaluated))
    dict(obj)
  }

  let errorResponse = (e: errorResponse) => {
    let obj = Js.Dict.empty()
    Js.Dict.set(obj, "error", string(e.error))
    Js.Dict.set(obj, "message", string(e.message))
    Js.Dict.set(obj, "statusCode", int(e.statusCode))
    dict(obj)
  }
}

// Version constant
let apiVersion = "0.1.0"

// Health check handler
let healthHandler = (_params, _query, _body) => {
  let now = Js.Date.make()->Js.Date.toISOString

  // Check services (mock for now - will be wired to actual clients)
  let services = Js.Dict.empty()
  Js.Dict.set(services, "surrealdb", "connected")
  Js.Dict.set(services, "xtdb", "connected")
  Js.Dict.set(services, "dragonfly", "connected")
  Js.Dict.set(services, "optimizer", "connected")

  let response: healthResponse = {
    status: "healthy",
    version: apiVersion,
    timestamp: now,
    services,
  }

  Js.Promise.resolve(Encode.healthResponse(response))
}

// List shipments handler
let listShipmentsHandler = (_params, query, _body) => {
  // Parse pagination from query
  let _limit =
    query
    ->Js.Dict.get("limit")
    ->Belt.Option.flatMap(Belt.Int.fromString)
    ->Belt.Option.getWithDefault(20)

  let _offset =
    query
    ->Js.Dict.get("offset")
    ->Belt.Option.flatMap(Belt.Int.fromString)
    ->Belt.Option.getWithDefault(0)

  // Mock response - will be replaced with actual DB query
  let shipments: array<shipment> = []

  let result = Js.Dict.empty()
  Js.Dict.set(result, "data", Js.Json.array(Js.Array2.map(shipments, Encode.shipment)))
  Js.Dict.set(result, "total", Js.Json.number(0.0))
  Js.Dict.set(result, "limit", Js.Json.number(20.0))
  Js.Dict.set(result, "offset", Js.Json.number(0.0))

  Js.Promise.resolve(Js.Json.object_(result))
}

// Get shipment by ID handler
let getShipmentHandler = (params, _query, _body) => {
  let shipmentId = params->Js.Dict.get("id")->Belt.Option.getWithDefault("")

  if Js.String2.length(shipmentId) == 0 {
    let error: errorResponse = {
      error: "not_found",
      message: "Shipment not found",
      statusCode: 404,
    }
    Js.Promise.resolve(Encode.errorResponse(error))
  } else {
    // Mock response - will be replaced with actual DB query
    let error: errorResponse = {
      error: "not_found",
      message: "Shipment " ++ shipmentId ++ " not found",
      statusCode: 404,
    }
    Js.Promise.resolve(Encode.errorResponse(error))
  }
}

// Create shipment handler
let createShipmentHandler = (_params, _query, body) => {
  switch body {
  | Some(_json) =>
    // Parse and validate shipment data
    // TODO: Implement proper JSON decoding
    let error: errorResponse = {
      error: "not_implemented",
      message: "Create shipment not yet implemented",
      statusCode: 501,
    }
    Js.Promise.resolve(Encode.errorResponse(error))
  | None =>
    let error: errorResponse = {
      error: "bad_request",
      message: "Request body is required",
      statusCode: 400,
    }
    Js.Promise.resolve(Encode.errorResponse(error))
  }
}

// Optimize routes for shipment handler
let optimizeRoutesHandler = (_params, _query, body) => {
  switch body {
  | Some(_json) =>
    // Parse optimize request and call gRPC optimizer
    // Mock response for now
    let response: optimizeResponse = {
      success: true,
      errorMessage: None,
      routes: [],
      optimizationTimeMs: 0,
      candidatesEvaluated: 0,
    }
    Js.Promise.resolve(Encode.optimizeResponse(response))
  | None =>
    let error: errorResponse = {
      error: "bad_request",
      message: "Request body is required",
      statusCode: 400,
    }
    Js.Promise.resolve(Encode.errorResponse(error))
  }
}

// List routes for shipment handler
let listRoutesHandler = (params, _query, _body) => {
  let _shipmentId = params->Js.Dict.get("shipmentId")->Belt.Option.getWithDefault("")

  // Mock response
  let routes: array<route> = []

  let result = Js.Dict.empty()
  Js.Dict.set(result, "data", Js.Json.array(Js.Array2.map(routes, Encode.route)))
  Js.Dict.set(result, "total", Js.Json.number(0.0))

  Js.Promise.resolve(Js.Json.object_(result))
}

// Select route handler
let selectRouteHandler = (params, _query, _body) => {
  let _shipmentId = params->Js.Dict.get("shipmentId")->Belt.Option.getWithDefault("")
  let _routeId = params->Js.Dict.get("routeId")->Belt.Option.getWithDefault("")

  let error: errorResponse = {
    error: "not_implemented",
    message: "Route selection not yet implemented",
    statusCode: 501,
  }
  Js.Promise.resolve(Encode.errorResponse(error))
}

// Get transport graph status handler
let graphStatusHandler = (_params, _query, _body) => {
  // Mock response - will call gRPC optimizer
  let result = Js.Dict.empty()
  Js.Dict.set(result, "nodeCount", Js.Json.number(0.0))
  Js.Dict.set(result, "edgeCount", Js.Json.number(0.0))
  Js.Dict.set(result, "lastLoaded", Js.Json.string(Js.Date.make()->Js.Date.toISOString))
  Js.Dict.set(result, "loadTimeMs", Js.Json.number(0.0))
  Js.Dict.set(result, "modeCounts", Js.Json.object_(Js.Dict.empty()))

  Js.Promise.resolve(Js.Json.object_(result))
}

// Reload transport graph handler
let reloadGraphHandler = (_params, _query, _body) => {
  // Mock response - will call gRPC optimizer
  let result = Js.Dict.empty()
  Js.Dict.set(result, "success", Js.Json.boolean(true))
  Js.Dict.set(result, "message", Js.Json.string("Graph reload initiated"))
  Js.Dict.set(result, "loadTimeMs", Js.Json.number(0.0))

  Js.Promise.resolve(Js.Json.object_(result))
}

// List constraints handler
let listConstraintsHandler = (_params, _query, _body) => {
  // Mock response
  let result = Js.Dict.empty()
  Js.Dict.set(result, "data", Js.Json.array([]))
  Js.Dict.set(result, "total", Js.Json.number(0.0))

  Js.Promise.resolve(Js.Json.object_(result))
}

// Evaluate constraints handler
let evaluateConstraintsHandler = (_params, _query, body) => {
  switch body {
  | Some(_json) =>
    // Parse and evaluate constraints
    let result = Js.Dict.empty()
    Js.Dict.set(result, "success", Js.Json.boolean(true))
    Js.Dict.set(result, "allHardPassed", Js.Json.boolean(true))
    Js.Dict.set(result, "overallScore", Js.Json.number(1.0))
    Js.Dict.set(result, "results", Js.Json.array([]))

    Js.Promise.resolve(Js.Json.object_(result))
  | None =>
    let error: errorResponse = {
      error: "bad_request",
      message: "Request body is required",
      statusCode: 400,
    }
    Js.Promise.resolve(Encode.errorResponse(error))
  }
}

// Not found handler
let notFoundHandler = (_params, _query, _body) => {
  let error: errorResponse = {
    error: "not_found",
    message: "Resource not found",
    statusCode: 404,
  }
  Js.Promise.resolve(Encode.errorResponse(error))
}

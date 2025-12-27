// SPDX-License-Identifier: MIT OR AGPL-3.0
// VEDS API - Deno HTTP Server Entry Point

// Note: ReScript modules are imported from compiled .res.js files
// Run `rescript build` first to compile the ReScript code

const VERSION = '0.1.0';

// Environment configuration
interface Config {
  port: number;
  host: string;
  surrealdbUrl: string;
  surrealdbUser: string;
  surrealdbPass: string;
  xtdbUrl: string;
  dragonflyUrl: string;
  dragonflyPass: string;
  optimizerUrl: string;
}

function loadConfig(): Config {
  return {
    port: parseInt(Deno.env.get('PORT') || '4000', 10),
    host: Deno.env.get('HOST') || '0.0.0.0',
    surrealdbUrl: Deno.env.get('SURREALDB_URL') || 'ws://localhost:8000',
    surrealdbUser: Deno.env.get('SURREALDB_USER') || 'root',
    surrealdbPass: Deno.env.get('SURREALDB_PASS') || 'veds_dev_password',
    xtdbUrl: Deno.env.get('XTDB_URL') || 'http://localhost:3000',
    dragonflyUrl: Deno.env.get('DRAGONFLY_URL') || 'redis://localhost:6379',
    dragonflyPass: Deno.env.get('DRAGONFLY_PASS') || 'veds_dev_password',
    optimizerUrl: Deno.env.get('OPTIMIZER_URL') || 'http://localhost:50051',
  };
}

// CORS headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Request-ID',
};

// JSON response helper
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders,
    },
  });
}

// Error response helper
function errorResponse(error: string, message: string, status: number): Response {
  return jsonResponse({ error, message, statusCode: status }, status);
}

// Route pattern matching
interface RouteMatch {
  params: Record<string, string>;
  handler: RouteHandler;
}

type RouteHandler = (
  req: Request,
  params: Record<string, string>,
  query: URLSearchParams
) => Promise<Response>;

interface Route {
  method: string;
  pattern: RegExp;
  paramNames: string[];
  handler: RouteHandler;
}

// Build routes
function createRoutes(): Route[] {
  return [
    // Health check
    {
      method: 'GET',
      pattern: /^\/health$/,
      paramNames: [],
      handler: handleHealth,
    },
    {
      method: 'GET',
      pattern: /^\/api\/v1\/health$/,
      paramNames: [],
      handler: handleHealth,
    },

    // Shipments
    {
      method: 'GET',
      pattern: /^\/api\/v1\/shipments$/,
      paramNames: [],
      handler: handleListShipments,
    },
    {
      method: 'POST',
      pattern: /^\/api\/v1\/shipments$/,
      paramNames: [],
      handler: handleCreateShipment,
    },
    {
      method: 'GET',
      pattern: /^\/api\/v1\/shipments\/([^/]+)$/,
      paramNames: ['id'],
      handler: handleGetShipment,
    },
    {
      method: 'PUT',
      pattern: /^\/api\/v1\/shipments\/([^/]+)$/,
      paramNames: ['id'],
      handler: handleUpdateShipment,
    },
    {
      method: 'DELETE',
      pattern: /^\/api\/v1\/shipments\/([^/]+)$/,
      paramNames: ['id'],
      handler: handleDeleteShipment,
    },

    // Routes optimization
    {
      method: 'POST',
      pattern: /^\/api\/v1\/shipments\/([^/]+)\/optimize$/,
      paramNames: ['shipmentId'],
      handler: handleOptimizeRoutes,
    },
    {
      method: 'GET',
      pattern: /^\/api\/v1\/shipments\/([^/]+)\/routes$/,
      paramNames: ['shipmentId'],
      handler: handleListRoutes,
    },
    {
      method: 'POST',
      pattern: /^\/api\/v1\/shipments\/([^/]+)\/routes\/([^/]+)\/select$/,
      paramNames: ['shipmentId', 'routeId'],
      handler: handleSelectRoute,
    },

    // Transport graph
    {
      method: 'GET',
      pattern: /^\/api\/v1\/graph\/status$/,
      paramNames: [],
      handler: handleGraphStatus,
    },
    {
      method: 'POST',
      pattern: /^\/api\/v1\/graph\/reload$/,
      paramNames: [],
      handler: handleReloadGraph,
    },
    {
      method: 'GET',
      pattern: /^\/api\/v1\/nodes$/,
      paramNames: [],
      handler: handleListNodes,
    },
    {
      method: 'GET',
      pattern: /^\/api\/v1\/edges$/,
      paramNames: [],
      handler: handleListEdges,
    },

    // Constraints
    {
      method: 'GET',
      pattern: /^\/api\/v1\/constraints$/,
      paramNames: [],
      handler: handleListConstraints,
    },
    {
      method: 'POST',
      pattern: /^\/api\/v1\/constraints$/,
      paramNames: [],
      handler: handleCreateConstraint,
    },
    {
      method: 'POST',
      pattern: /^\/api\/v1\/constraints\/evaluate$/,
      paramNames: [],
      handler: handleEvaluateConstraints,
    },
    {
      method: 'GET',
      pattern: /^\/api\/v1\/constraints\/([^/]+)$/,
      paramNames: ['id'],
      handler: handleGetConstraint,
    },
    {
      method: 'PUT',
      pattern: /^\/api\/v1\/constraints\/([^/]+)$/,
      paramNames: ['id'],
      handler: handleUpdateConstraint,
    },

    // Tracking
    {
      method: 'GET',
      pattern: /^\/api\/v1\/tracking\/([^/]+)$/,
      paramNames: ['shipmentId'],
      handler: handleGetTracking,
    },
    {
      method: 'POST',
      pattern: /^\/api\/v1\/tracking\/([^/]+)\/positions$/,
      paramNames: ['shipmentId'],
      handler: handleAddPosition,
    },
  ];
}

// Route matching
function matchRoute(routes: Route[], method: string, pathname: string): RouteMatch | null {
  for (const route of routes) {
    if (route.method !== method) continue;

    const match = pathname.match(route.pattern);
    if (match) {
      const params: Record<string, string> = {};
      route.paramNames.forEach((name, i) => {
        params[name] = match[i + 1];
      });
      return { params, handler: route.handler };
    }
  }
  return null;
}

// Handlers
async function handleHealth(_req: Request): Promise<Response> {
  const services: Record<string, string> = {
    surrealdb: 'connected',
    xtdb: 'connected',
    dragonfly: 'connected',
    optimizer: 'connected',
  };

  return jsonResponse({
    status: 'healthy',
    version: VERSION,
    timestamp: new Date().toISOString(),
    services,
  });
}

async function handleListShipments(
  _req: Request,
  _params: Record<string, string>,
  query: URLSearchParams
): Promise<Response> {
  const limit = parseInt(query.get('limit') || '20', 10);
  const offset = parseInt(query.get('offset') || '0', 10);

  // TODO: Query SurrealDB
  return jsonResponse({
    data: [],
    total: 0,
    limit,
    offset,
  });
}

async function handleGetShipment(
  _req: Request,
  params: Record<string, string>
): Promise<Response> {
  const { id } = params;

  // TODO: Query SurrealDB
  return errorResponse('not_found', `Shipment ${id} not found`, 404);
}

async function handleCreateShipment(req: Request): Promise<Response> {
  try {
    const body = await req.json();

    // Validate required fields
    const required = ['customerId', 'origin', 'destination', 'weightKg'];
    for (const field of required) {
      if (!(field in body)) {
        return errorResponse('validation_error', `Missing required field: ${field}`, 400);
      }
    }

    // TODO: Insert into SurrealDB
    return jsonResponse({ id: crypto.randomUUID(), ...body }, 201);
  } catch {
    return errorResponse('bad_request', 'Invalid JSON body', 400);
  }
}

async function handleUpdateShipment(
  req: Request,
  params: Record<string, string>
): Promise<Response> {
  const { id } = params;

  try {
    const body = await req.json();
    // TODO: Update in SurrealDB
    return jsonResponse({ id, ...body });
  } catch {
    return errorResponse('bad_request', 'Invalid JSON body', 400);
  }
}

async function handleDeleteShipment(
  _req: Request,
  params: Record<string, string>
): Promise<Response> {
  const { id } = params;
  // TODO: Delete from SurrealDB
  return jsonResponse({ deleted: true, id });
}

async function handleOptimizeRoutes(
  req: Request,
  params: Record<string, string>
): Promise<Response> {
  const { shipmentId } = params;

  try {
    const body = await req.json();

    // Build optimization request
    const optimizeRequest = {
      shipmentId,
      originPort: body.originPort || '',
      destinationPort: body.destinationPort || '',
      weightKg: body.weightKg || 1000,
      volumeM3: body.volumeM3 || 1,
      pickupAfter: body.pickupAfter || new Date().toISOString(),
      deliverBy: body.deliverBy || new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
      maxCostUsd: body.maxCostUsd,
      maxCarbonKg: body.maxCarbonKg,
      minLaborScore: body.minLaborScore,
      allowedModes: body.allowedModes || [],
      excludedCarriers: body.excludedCarriers || [],
      maxRoutes: body.maxRoutes || 10,
      maxSegments: body.maxSegments || 8,
      costWeight: body.costWeight || 0.4,
      timeWeight: body.timeWeight || 0.3,
      carbonWeight: body.carbonWeight || 0.2,
      laborWeight: body.laborWeight || 0.1,
    };

    // TODO: Call gRPC optimizer
    return jsonResponse({
      success: true,
      shipmentId,
      routes: [],
      optimizationTimeMs: 0,
      candidatesEvaluated: 0,
    });
  } catch {
    return errorResponse('bad_request', 'Invalid JSON body', 400);
  }
}

async function handleListRoutes(
  _req: Request,
  params: Record<string, string>
): Promise<Response> {
  const { shipmentId } = params;

  // TODO: Query SurrealDB for routes
  return jsonResponse({
    shipmentId,
    data: [],
    total: 0,
  });
}

async function handleSelectRoute(
  _req: Request,
  params: Record<string, string>
): Promise<Response> {
  const { shipmentId, routeId } = params;

  // TODO: Update route status in SurrealDB
  return jsonResponse({
    success: true,
    shipmentId,
    routeId,
    message: 'Route selected',
  });
}

async function handleGraphStatus(_req: Request): Promise<Response> {
  // TODO: Call gRPC optimizer
  return jsonResponse({
    nodeCount: 0,
    edgeCount: 0,
    lastLoaded: new Date().toISOString(),
    loadTimeMs: 0,
    modeCounts: {},
  });
}

async function handleReloadGraph(_req: Request): Promise<Response> {
  // TODO: Call gRPC optimizer
  return jsonResponse({
    success: true,
    message: 'Graph reload initiated',
    loadTimeMs: 0,
  });
}

async function handleListNodes(
  _req: Request,
  _params: Record<string, string>,
  query: URLSearchParams
): Promise<Response> {
  const limit = parseInt(query.get('limit') || '100', 10);
  const offset = parseInt(query.get('offset') || '0', 10);

  // TODO: Query SurrealDB
  return jsonResponse({
    data: [],
    total: 0,
    limit,
    offset,
  });
}

async function handleListEdges(
  _req: Request,
  _params: Record<string, string>,
  query: URLSearchParams
): Promise<Response> {
  const limit = parseInt(query.get('limit') || '100', 10);
  const offset = parseInt(query.get('offset') || '0', 10);
  const mode = query.get('mode');

  // TODO: Query SurrealDB
  return jsonResponse({
    data: [],
    total: 0,
    limit,
    offset,
    mode,
  });
}

async function handleListConstraints(_req: Request): Promise<Response> {
  // TODO: Query XTDB
  return jsonResponse({
    data: [],
    total: 0,
  });
}

async function handleCreateConstraint(req: Request): Promise<Response> {
  try {
    const body = await req.json();

    // Validate
    if (!body.name || !body.constraintType) {
      return errorResponse('validation_error', 'Missing required fields', 400);
    }

    // TODO: Insert into XTDB
    return jsonResponse({ id: crypto.randomUUID(), ...body }, 201);
  } catch {
    return errorResponse('bad_request', 'Invalid JSON body', 400);
  }
}

async function handleGetConstraint(
  _req: Request,
  params: Record<string, string>
): Promise<Response> {
  const { id } = params;
  // TODO: Query XTDB
  return errorResponse('not_found', `Constraint ${id} not found`, 404);
}

async function handleUpdateConstraint(
  req: Request,
  params: Record<string, string>
): Promise<Response> {
  const { id } = params;

  try {
    const body = await req.json();
    // TODO: Update in XTDB
    return jsonResponse({ id, ...body });
  } catch {
    return errorResponse('bad_request', 'Invalid JSON body', 400);
  }
}

async function handleEvaluateConstraints(req: Request): Promise<Response> {
  try {
    const body = await req.json();

    if (!body.route) {
      return errorResponse('validation_error', 'Route is required', 400);
    }

    // TODO: Call gRPC optimizer or evaluate locally
    return jsonResponse({
      success: true,
      allHardPassed: true,
      overallScore: 1.0,
      results: [],
    });
  } catch {
    return errorResponse('bad_request', 'Invalid JSON body', 400);
  }
}

async function handleGetTracking(
  _req: Request,
  params: Record<string, string>
): Promise<Response> {
  const { shipmentId } = params;

  // TODO: Query Dragonfly for latest position
  return jsonResponse({
    shipmentId,
    positions: [],
    lastUpdated: null,
  });
}

async function handleAddPosition(
  req: Request,
  params: Record<string, string>
): Promise<Response> {
  const { shipmentId } = params;

  try {
    const body = await req.json();

    // Validate
    if (!body.lat || !body.lon) {
      return errorResponse('validation_error', 'lat and lon are required', 400);
    }

    // TODO: Store in Dragonfly and SurrealDB
    return jsonResponse({
      success: true,
      shipmentId,
      position: body,
      timestamp: new Date().toISOString(),
    });
  } catch {
    return errorResponse('bad_request', 'Invalid JSON body', 400);
  }
}

// Main server
async function main() {
  const config = loadConfig();
  const routes = createRoutes();

  console.log(`VEDS API v${VERSION}`);
  console.log(`Starting server on ${config.host}:${config.port}`);

  Deno.serve({ port: config.port, hostname: config.host }, async (req) => {
    const url = new URL(req.url);
    const method = req.method;
    const pathname = url.pathname;

    // Handle CORS preflight
    if (method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    // Request logging
    const requestId = crypto.randomUUID().slice(0, 8);
    const start = performance.now();
    console.log(`[${requestId}] ${method} ${pathname}`);

    // Route matching
    const match = matchRoute(routes, method, pathname);

    let response: Response;
    if (match) {
      try {
        response = await match.handler(req, match.params, url.searchParams);
      } catch (err) {
        console.error(`[${requestId}] Error:`, err);
        response = errorResponse('internal_error', 'Internal server error', 500);
      }
    } else {
      response = errorResponse('not_found', `Route ${method} ${pathname} not found`, 404);
    }

    // Response logging
    const duration = (performance.now() - start).toFixed(2);
    console.log(`[${requestId}] ${response.status} (${duration}ms)`);

    return response;
  });
}

main();

// SPDX-License-Identifier: MIT OR AGPL-3.0
// VEDS Constraint DSL - Declarative constraint definitions

open Types

// =============================================================================
// CONSTRAINT VALUE TYPES
// =============================================================================

// Comparison operators
type comparison =
  | Eq
  | Ne
  | Lt
  | Lte
  | Gt
  | Gte

// Value types for constraint expressions
type rec value =
  | VInt(int)
  | VFloat(float)
  | VString(string)
  | VBool(bool)
  | VArray(array<value>)
  | VNull

// Field references
type fieldRef =
  | RouteField(string)
  | SegmentField(string)
  | CarrierField(string)
  | ShipmentField(string)

// =============================================================================
// CONSTRAINT EXPRESSION AST
// =============================================================================

// Boolean expressions for constraints
type rec expr =
  // Comparison expressions
  | Compare(fieldRef, comparison, value)
  // Logical operators
  | And(expr, expr)
  | Or(expr, expr)
  | Not(expr)
  // Aggregate expressions (over segments)
  | All(string, expr) // All segments match
  | Any(string, expr) // Any segment matches
  | Sum(string, fieldRef, comparison, value) // Sum of field compared to value
  | Avg(string, fieldRef, comparison, value) // Average of field compared to value
  | Count(string, expr, comparison, value) // Count matching compared to value
  // Special expressions
  | InSet(fieldRef, array<value>) // Field value in set
  | NotInSet(fieldRef, array<value>) // Field value not in set
  | Between(fieldRef, value, value) // Field value between two values
  | Exists(fieldRef) // Field exists and is not null
  // Literal
  | Literal(bool)

// =============================================================================
// CONSTRAINT DEFINITION
// =============================================================================

// Constraint scope
type scope = Global | Customer(string) | Shipment(string) | Route(string)

// Constraint definition
type constraint_ = {
  id: string,
  name: string,
  description: string,
  constraintType: string,
  isHard: bool,
  priority: int,
  scope: scope,
  expression: expr,
  params: Js.Dict.t<value>,
  effectiveFrom: option<string>,
  effectiveUntil: option<string>,
}

// =============================================================================
// DSL BUILDER FUNCTIONS
// =============================================================================

module DSL = {
  // Field references
  let routeField = name => RouteField(name)
  let segmentField = name => SegmentField(name)
  let carrierField = name => CarrierField(name)
  let shipmentField = name => ShipmentField(name)

  // Values
  let int = n => VInt(n)
  let float = n => VFloat(n)
  let string = s => VString(s)
  let bool = b => VBool(b)
  let array = arr => VArray(arr)
  let null = VNull

  // Comparisons
  let eq = (field, value) => Compare(field, Eq, value)
  let ne = (field, value) => Compare(field, Ne, value)
  let lt = (field, value) => Compare(field, Lt, value)
  let lte = (field, value) => Compare(field, Lte, value)
  let gt = (field, value) => Compare(field, Gt, value)
  let gte = (field, value) => Compare(field, Gte, value)

  // Logical operators
  let and_ = (a, b) => And(a, b)
  let or_ = (a, b) => Or(a, b)
  let not_ = e => Not(e)

  // Aggregate expressions
  let all = (binding, expr) => All(binding, expr)
  let any = (binding, expr) => Any(binding, expr)
  let sum = (binding, field, cmp, value) => Sum(binding, field, cmp, value)
  let avg = (binding, field, cmp, value) => Avg(binding, field, cmp, value)
  let count = (binding, pred, cmp, value) => Count(binding, pred, cmp, value)

  // Set operations
  let inSet = (field, values) => InSet(field, values)
  let notInSet = (field, values) => NotInSet(field, values)

  // Range
  let between = (field, low, high) => Between(field, low, high)

  // Existence
  let exists = field => Exists(field)

  // Literals
  let true_ = Literal(true)
  let false_ = Literal(false)

  // Constraint builders
  let constraint_ = (~id, ~name, ~constraintType, ~isHard, ~expression) => {
    id,
    name,
    description: "",
    constraintType,
    isHard,
    priority: 100,
    scope: Global,
    expression,
    params: Js.Dict.empty(),
    effectiveFrom: None,
    effectiveUntil: None,
  }

  let withDescription = (c, desc) => {...c, description: desc}
  let withPriority = (c, p) => {...c, priority: p}
  let withScope = (c, s) => {...c, scope: s}
  let withParams = (c, p) => {...c, params: p}
  let withEffective = (c, from, until) => {...c, effectiveFrom: from, effectiveUntil: until}
}

// =============================================================================
// BUILT-IN CONSTRAINT TEMPLATES
// =============================================================================

module Templates = {
  open DSL

  // Minimum wage constraint
  let minWage = minWageCents =>
    constraint_(
      ~id="min-wage",
      ~name="Minimum Wage Compliance",
      ~constraintType="wage",
      ~isHard=true,
      ~expression=all(
        "segment",
        gte(segmentField("carrierWageCents"), int(minWageCents)),
      ),
    )->withDescription("Ensure all carrier wages meet minimum requirements")

  // No sanctioned carriers
  let noSanctionedCarriers = sanctionedList =>
    constraint_(
      ~id="no-sanctioned-carriers",
      ~name="Sanctions Compliance",
      ~constraintType="sanction",
      ~isHard=true,
      ~expression=all(
        "segment",
        notInSet(segmentField("carrierCode"), sanctionedList),
      ),
    )->withDescription("Ensure no sanctioned carriers are used")

  // Carbon budget
  let carbonBudget = maxCarbonKg =>
    constraint_(
      ~id="carbon-budget",
      ~name="Carbon Budget Limit",
      ~constraintType="carbon",
      ~isHard=false,
      ~expression=lte(routeField("totalCarbonKg"), float(maxCarbonKg)),
    )->withDescription("Total carbon emissions under budget")

  // Cost budget
  let costBudget = maxCostUsd =>
    constraint_(
      ~id="cost-budget",
      ~name="Cost Budget Limit",
      ~constraintType="cost",
      ~isHard=false,
      ~expression=lte(routeField("totalCostUsd"), float(maxCostUsd)),
    )->withDescription("Total cost under budget")

  // Time window
  let timeWindow = maxHours =>
    constraint_(
      ~id="time-window",
      ~name="Delivery Time Window",
      ~constraintType="time",
      ~isHard=true,
      ~expression=lte(routeField("totalTransitHours"), float(maxHours)),
    )->withDescription("Delivery within time window")

  // Minimum safety rating
  let minSafetyRating = minRating =>
    constraint_(
      ~id="min-safety-rating",
      ~name="Minimum Safety Rating",
      ~constraintType="safety",
      ~isHard=false,
      ~expression=all(
        "segment",
        gte(carrierField("safetyRating"), int(minRating)),
      ),
    )->withDescription("All carriers meet minimum safety rating")

  // Union preference (soft constraint)
  let unionPreference = () =>
    constraint_(
      ~id="union-preference",
      ~name="Union Carrier Preference",
      ~constraintType="wage",
      ~isHard=false,
      ~expression=any("segment", eq(carrierField("unionized"), bool(true))),
    )->withDescription("Prefer unionized carriers")

  // Maximum segments
  let maxSegments = max =>
    constraint_(
      ~id="max-segments",
      ~name="Maximum Route Segments",
      ~constraintType="route",
      ~isHard=false,
      ~expression=lte(routeField("segmentCount"), int(max)),
    )->withDescription("Limit number of route segments")

  // Minimum labor score
  let minLaborScore = minScore =>
    constraint_(
      ~id="min-labor-score",
      ~name="Minimum Labor Score",
      ~constraintType="wage",
      ~isHard=false,
      ~expression=gte(routeField("laborScore"), float(minScore)),
    )->withDescription("Route meets minimum labor score")

  // Mode restrictions
  let allowedModes = modes =>
    constraint_(
      ~id="allowed-modes",
      ~name="Allowed Transport Modes",
      ~constraintType="mode",
      ~isHard=true,
      ~expression=all("segment", inSet(segmentField("mode"), modes)),
    )->withDescription("Only specified transport modes allowed")
}

// =============================================================================
// EVALUATION CONTEXT
// =============================================================================

// Evaluation context containing runtime values
type evalContext = {
  route: route,
  shipment: option<shipment>,
  params: Js.Dict.t<value>,
}

// =============================================================================
// CONSTRAINT EVALUATION
// =============================================================================

// Get field value from route
let getRouteFieldValue = (route: route, fieldName: string): option<value> => {
  switch fieldName {
  | "totalCostUsd" => Some(VFloat(route.totalCostUsd))
  | "totalCarbonKg" => Some(VFloat(route.totalCarbonKg))
  | "totalTransitHours" => Some(VFloat(route.totalTransitHours))
  | "totalDistanceKm" => Some(VFloat(route.totalDistanceKm))
  | "laborScore" => Some(VFloat(route.laborScore))
  | "constraintScore" => Some(VFloat(route.constraintScore))
  | "paretoRank" => Some(VInt(route.paretoRank))
  | "segmentCount" => Some(VInt(Js.Array2.length(route.segments)))
  | _ => None
  }
}

// Get field value from segment
let getSegmentFieldValue = (segment: routeSegment, fieldName: string): option<value> => {
  switch fieldName {
  | "distanceKm" => Some(VFloat(segment.distanceKm))
  | "costUsd" => Some(VFloat(segment.costUsd))
  | "transitHours" => Some(VFloat(segment.transitHours))
  | "carbonKg" => Some(VFloat(segment.carbonKg))
  | "carrierWageCents" => Some(VInt(segment.carrierWageCents))
  | "laborScore" => Some(VFloat(segment.laborScore))
  | "carrierCode" => Some(VString(segment.carrierCode))
  | "mode" => Some(VString(transportModeToString(segment.mode)))
  | "sequence" => Some(VInt(segment.sequence))
  | _ => None
  }
}

// Compare two values
let compareValues = (v1: value, op: comparison, v2: value): bool => {
  switch (v1, v2) {
  | (VInt(a), VInt(b)) =>
    switch op {
    | Eq => a == b
    | Ne => a != b
    | Lt => a < b
    | Lte => a <= b
    | Gt => a > b
    | Gte => a >= b
    }
  | (VFloat(a), VFloat(b)) =>
    switch op {
    | Eq => a == b
    | Ne => a != b
    | Lt => a < b
    | Lte => a <= b
    | Gt => a > b
    | Gte => a >= b
    }
  | (VInt(a), VFloat(b)) =>
    let af = Js.Int.toFloat(a)
    switch op {
    | Eq => af == b
    | Ne => af != b
    | Lt => af < b
    | Lte => af <= b
    | Gt => af > b
    | Gte => af >= b
    }
  | (VFloat(a), VInt(b)) =>
    let bf = Js.Int.toFloat(b)
    switch op {
    | Eq => a == bf
    | Ne => a != bf
    | Lt => a < bf
    | Lte => a <= bf
    | Gt => a > bf
    | Gte => a >= bf
    }
  | (VString(a), VString(b)) =>
    switch op {
    | Eq => a == b
    | Ne => a != b
    | Lt => a < b
    | Lte => a <= b
    | Gt => a > b
    | Gte => a >= b
    }
  | (VBool(a), VBool(b)) =>
    switch op {
    | Eq => a == b
    | Ne => a != b
    | _ => false
    }
  | _ => false
  }
}

// Check if value is in set
let valueInSet = (value: value, set: array<value>): bool => {
  set->Js.Array2.some(v => compareValues(value, Eq, v))
}

// Evaluate expression
let rec evaluate = (expr: expr, ctx: evalContext): bool => {
  switch expr {
  | Literal(b) => b

  | Compare(field, op, value) =>
    let fieldValue = switch field {
    | RouteField(name) => getRouteFieldValue(ctx.route, name)
    | SegmentField(_) => None // Need segment context
    | CarrierField(_) => None // Need segment context
    | ShipmentField(_) => None // Need shipment context
    }
    switch fieldValue {
    | Some(fv) => compareValues(fv, op, value)
    | None => false
    }

  | And(a, b) => evaluate(a, ctx) && evaluate(b, ctx)

  | Or(a, b) => evaluate(a, ctx) || evaluate(b, ctx)

  | Not(e) => !evaluate(e, ctx)

  | All(_, innerExpr) =>
    ctx.route.segments->Js.Array2.every(segment => {
      let segmentCtx = {...ctx, route: {...ctx.route, segments: [segment]}}
      evaluateWithSegment(innerExpr, segmentCtx, segment)
    })

  | Any(_, innerExpr) =>
    ctx.route.segments->Js.Array2.some(segment => {
      let segmentCtx = {...ctx, route: {...ctx.route, segments: [segment]}}
      evaluateWithSegment(innerExpr, segmentCtx, segment)
    })

  | Sum(_, field, op, value) =>
    let sum = ctx.route.segments->Js.Array2.reduce((acc, seg) => {
      switch field {
      | SegmentField(name) =>
        switch getSegmentFieldValue(seg, name) {
        | Some(VFloat(v)) => acc +. v
        | Some(VInt(v)) => acc +. Js.Int.toFloat(v)
        | _ => acc
        }
      | _ => acc
      }
    }, 0.0)
    compareValues(VFloat(sum), op, value)

  | Avg(_, field, op, value) =>
    let (sum, count) = ctx.route.segments->Js.Array2.reduce(((s, c), seg) => {
      switch field {
      | SegmentField(name) =>
        switch getSegmentFieldValue(seg, name) {
        | Some(VFloat(v)) => (s +. v, c + 1)
        | Some(VInt(v)) => (s +. Js.Int.toFloat(v), c + 1)
        | _ => (s, c)
        }
      | _ => (s, c)
      }
    }, (0.0, 0))
    let avg = if count > 0 {
      sum /. Js.Int.toFloat(count)
    } else {
      0.0
    }
    compareValues(VFloat(avg), op, value)

  | Count(_, pred, op, value) =>
    let count = ctx.route.segments->Js.Array2.reduce((acc, seg) => {
      let segmentCtx = {...ctx, route: {...ctx.route, segments: [seg]}}
      if evaluateWithSegment(pred, segmentCtx, seg) {
        acc + 1
      } else {
        acc
      }
    }, 0)
    compareValues(VInt(count), op, value)

  | InSet(field, values) =>
    switch field {
    | RouteField(name) =>
      switch getRouteFieldValue(ctx.route, name) {
      | Some(fv) => valueInSet(fv, values)
      | None => false
      }
    | _ => false
    }

  | NotInSet(field, values) => !evaluate(InSet(field, values), ctx)

  | Between(field, low, high) =>
    evaluate(And(Compare(field, Gte, low), Compare(field, Lte, high)), ctx)

  | Exists(field) =>
    switch field {
    | RouteField(name) => getRouteFieldValue(ctx.route, name)->Belt.Option.isSome
    | _ => false
    }
  }
}

and evaluateWithSegment = (expr: expr, ctx: evalContext, segment: routeSegment): bool => {
  switch expr {
  | Compare(field, op, value) =>
    let fieldValue = switch field {
    | RouteField(name) => getRouteFieldValue(ctx.route, name)
    | SegmentField(name) => getSegmentFieldValue(segment, name)
    | CarrierField(name) =>
      // Map carrier fields to segment values
      switch name {
      | "code" => Some(VString(segment.carrierCode))
      | "safetyRating" => Some(VInt(3)) // TODO: Get from carrier data
      | "unionized" => Some(VBool(false)) // TODO: Get from carrier data
      | _ => None
      }
    | ShipmentField(_) => None
    }
    switch fieldValue {
    | Some(fv) => compareValues(fv, op, value)
    | None => false
    }

  | InSet(field, values) =>
    let fieldValue = switch field {
    | SegmentField(name) => getSegmentFieldValue(segment, name)
    | _ => None
    }
    switch fieldValue {
    | Some(fv) => valueInSet(fv, values)
    | None => false
    }

  | NotInSet(field, values) => !evaluateWithSegment(InSet(field, values), ctx, segment)

  | And(a, b) =>
    evaluateWithSegment(a, ctx, segment) && evaluateWithSegment(b, ctx, segment)

  | Or(a, b) =>
    evaluateWithSegment(a, ctx, segment) || evaluateWithSegment(b, ctx, segment)

  | Not(e) => !evaluateWithSegment(e, ctx, segment)

  | _ => evaluate(expr, ctx)
  }
}

// Evaluate a constraint against a route
let evaluateConstraint = (constraint_: constraint_, route: route): constraintResult => {
  let ctx: evalContext = {
    route,
    shipment: None,
    params: constraint_.params,
  }

  let passed = evaluate(constraint_.expression, ctx)

  {
    constraintId: constraint_.id,
    constraintType: constraint_.constraintType,
    passed,
    isHard: constraint_.isHard,
    score: passed ? 1.0 : 0.0,
    message: passed
      ? constraint_.name ++ ": Passed"
      : constraint_.name ++ ": Failed",
  }
}

// Evaluate multiple constraints
let evaluateConstraints = (constraints: array<constraint_>, route: route): array<constraintResult> => {
  constraints->Js.Array2.map(c => evaluateConstraint(c, route))
}

// Check if all hard constraints pass
let allHardConstraintsPassed = (results: array<constraintResult>): bool => {
  results->Js.Array2.every(r => !r.isHard || r.passed)
}

// Calculate overall constraint score
let overallScore = (results: array<constraintResult>): float => {
  let len = Js.Array2.length(results)
  if len == 0 {
    1.0
  } else {
    let sum = results->Js.Array2.reduce((acc, r) => acc +. r.score, 0.0)
    sum /. Js.Int.toFloat(len)
  }
}

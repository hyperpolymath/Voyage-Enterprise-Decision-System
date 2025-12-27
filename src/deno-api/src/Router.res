// SPDX-License-Identifier: MIT OR AGPL-3.0
// VEDS API Router - Route handling and dispatch

// HTTP Method type
type httpMethod = GET | POST | PUT | PATCH | DELETE | OPTIONS

let methodFromString = str =>
  switch Js.String2.toUpperCase(str) {
  | "GET" => Some(GET)
  | "POST" => Some(POST)
  | "PUT" => Some(PUT)
  | "PATCH" => Some(PATCH)
  | "DELETE" => Some(DELETE)
  | "OPTIONS" => Some(OPTIONS)
  | _ => None
  }

// Route pattern matching result
type routeMatch = {
  params: Js.Dict.t<string>,
  query: Js.Dict.t<string>,
}

// Route handler type
type handler = (Js.Dict.t<string>, Js.Dict.t<string>, option<Js.Json.t>) => Js.Promise.t<Js.Json.t>

// Route definition
type routeDef = {
  method: httpMethod,
  pattern: string,
  handler: handler,
}

// Router state
type t = {routes: array<routeDef>}

// Create empty router
let make = () => {routes: []}

// Add a route
let addRoute = (router, method, pattern, handler) => {
  routes: Js.Array2.concat(router.routes, [{method, pattern, handler}]),
}

// Convenience methods
let get = (router, pattern, handler) => addRoute(router, GET, pattern, handler)
let post = (router, pattern, handler) => addRoute(router, POST, pattern, handler)
let put = (router, pattern, handler) => addRoute(router, PUT, pattern, handler)
let patch = (router, pattern, handler) => addRoute(router, PATCH, pattern, handler)
let delete = (router, pattern, handler) => addRoute(router, DELETE, pattern, handler)

// Pattern matching for routes
// Supports :param syntax (e.g., /shipments/:id)
let matchPattern = (pattern: string, path: string): option<Js.Dict.t<string>> => {
  let patternParts = Js.String2.split(pattern, "/")
  let pathParts = Js.String2.split(path, "/")

  if Js.Array2.length(patternParts) != Js.Array2.length(pathParts) {
    None
  } else {
    let params = Js.Dict.empty()
    let matched = ref(true)

    patternParts->Js.Array2.forEachi((part, i) => {
      let pathPart = pathParts->Js.Array2.unsafe_get(i)
      if Js.String2.startsWith(part, ":") {
        let paramName = Js.String2.sliceToEnd(part, ~from=1)
        Js.Dict.set(params, paramName, pathPart)
      } else if part != pathPart {
        matched := false
      }
    })

    if matched.contents {
      Some(params)
    } else {
      None
    }
  }
}

// Parse query string
let parseQuery = (queryString: string): Js.Dict.t<string> => {
  let query = Js.Dict.empty()
  if Js.String2.length(queryString) > 0 {
    let pairs = Js.String2.split(queryString, "&")
    pairs->Js.Array2.forEach(pair => {
      switch Js.String2.split(pair, "=") {
      | [key, value] =>
        Js.Dict.set(query, Js.Global.decodeURIComponent(key), Js.Global.decodeURIComponent(value))
      | [key] => Js.Dict.set(query, Js.Global.decodeURIComponent(key), "")
      | _ => ()
      }
    })
  }
  query
}

// Find matching route
let findRoute = (router, method, path) => {
  let normalizedPath =
    path
    ->Js.String2.split("?")
    ->Js.Array2.unsafe_get(0)

  router.routes->Js.Array2.find(route =>
    route.method == method && matchPattern(route.pattern, normalizedPath)->Belt.Option.isSome
  )
}

// Dispatch request to handler
let dispatch = (router, method, path, body) => {
  let normalizedPath =
    path
    ->Js.String2.split("?")
    ->Js.Array2.unsafe_get(0)

  let queryString = switch Js.String2.split(path, "?") {
  | [_, qs] => qs
  | _ => ""
  }
  let query = parseQuery(queryString)

  switch findRoute(router, method, path) {
  | Some(route) =>
    switch matchPattern(route.pattern, normalizedPath) {
    | Some(params) => route.handler(params, query, body)
    | None => Js.Promise.resolve(Js.Json.null)
    }
  | None => Js.Promise.resolve(Js.Json.null)
  }
}

// CORS headers helper
let corsHeaders = () => {
  let headers = Js.Dict.empty()
  Js.Dict.set(headers, "Access-Control-Allow-Origin", "*")
  Js.Dict.set(headers, "Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
  Js.Dict.set(headers, "Access-Control-Allow-Headers", "Content-Type, Authorization")
  headers
}

// JSON response helper
let jsonResponse = (data: Js.Json.t, status: int): (Js.Json.t, int, Js.Dict.t<string>) => {
  let headers = Js.Dict.empty()
  Js.Dict.set(headers, "Content-Type", "application/json")
  (data, status, headers)
}

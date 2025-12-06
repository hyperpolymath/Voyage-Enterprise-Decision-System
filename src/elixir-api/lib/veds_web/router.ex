defmodule VedsWeb.Router do
  use VedsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VedsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug VedsWeb.Plugs.ApiAuth
  end

  # API v1 routes
  scope "/api/v1", VedsWeb.API.V1 do
    pipe_through :api

    # Shipments
    resources "/shipments", ShipmentController, except: [:new, :edit]
    post "/shipments/:id/optimize", ShipmentController, :optimize
    get "/shipments/:id/routes", ShipmentController, :routes

    # Routes
    get "/routes/:id", RouteController, :show
    post "/routes/:id/select", RouteController, :select
    get "/routes/:id/proof", RouteController, :proof

    # Tracking
    get "/tracking/:shipment_id", TrackingController, :show
    get "/tracking/:shipment_id/history", TrackingController, :history
    get "/tracking/:shipment_id/eta", TrackingController, :eta

    # Constraints
    resources "/constraints", ConstraintController, except: [:new, :edit]
    post "/constraints/evaluate", ConstraintController, :evaluate

    # Audit
    get "/audit/:entity_type/:entity_id", AuditController, :show
    get "/audit/:entity_type/:entity_id/as-of/:timestamp", AuditController, :as_of

    # Network
    get "/network/nodes", NetworkController, :nodes
    get "/network/edges", NetworkController, :edges
    get "/network/status", NetworkController, :status

    # Health
    get "/health", HealthController, :check
  end

  # Dashboard (browser)
  scope "/", VedsWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/shipments", ShipmentLive.Index, :index
    live "/shipments/:id", ShipmentLive.Show, :show
    live "/network", NetworkLive, :index
    live "/analytics", AnalyticsLive, :index
  end

  # Phoenix LiveDashboard
  if Application.compile_env(:veds, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard",
        metrics: VedsWeb.Telemetry,
        ecto_repos: []
    end
  end
end

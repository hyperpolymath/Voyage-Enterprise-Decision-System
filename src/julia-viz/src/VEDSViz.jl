"""
VEDS Visualization Module

Provides interactive visualization for multi-modal transport routes,
Pareto frontiers, constraint violations, and real-time tracking.

Uses Makie ecosystem for high-performance graphics:
- GeoMakie: Geographic projections
- GraphMakie: Network topology
- WGLMakie: WebGL for browser rendering
"""
module VEDSViz

using Dates
using Colors
using Graphs
using StaticArrays

# Core visualization backends
using CairoMakie
using GeoMakie
using GraphMakie
using WGLMakie

# Data handling
using JSON3
using StructTypes

# Database connectivity
using LibPQ
using Redis

# Web framework
using Genie
using HTTP
using Observables

# =============================================================================
# Exports
# =============================================================================

export VEDSApp
export start_server, stop_server
export render_route_map, render_pareto_frontier, render_network_graph
export render_constraint_dashboard, render_carbon_breakdown
export subscribe_tracking_updates

# =============================================================================
# Data Types
# =============================================================================

"""Route segment with geographic and metadata"""
struct Segment
    id::String
    origin_lat::Float64
    origin_lon::Float64
    dest_lat::Float64
    dest_lon::Float64
    mode::Symbol  # :maritime, :rail, :road, :air
    carrier::String
    cost_usd::Float64
    time_hours::Float64
    carbon_kg::Float64
    wage_cents::Int
end

StructTypes.StructType(::Type{Segment}) = StructTypes.Struct()

"""Complete route with multiple segments"""
struct Route
    id::String
    segments::Vector{Segment}
    total_cost::Float64
    total_time::Float64
    total_carbon::Float64
    pareto_rank::Int
    constraint_violations::Vector{String}
end

StructTypes.StructType(::Type{Route}) = StructTypes.Struct()

"""Tracking event for real-time visualization"""
struct TrackingEvent
    shipment_id::String
    timestamp::DateTime
    lat::Float64
    lon::Float64
    status::Symbol
    carrier::String
    eta_hours::Float64
end

StructTypes.StructType(::Type{TrackingEvent}) = StructTypes.Struct()

"""Pareto point for multi-objective visualization"""
struct ParetoPoint
    route_id::String
    cost::Float64
    time::Float64
    carbon::Float64
    labor_score::Float64
    is_pareto_optimal::Bool
end

# =============================================================================
# Color Schemes
# =============================================================================

const MODE_COLORS = Dict(
    :maritime => colorant"#1E88E5",  # Blue
    :rail => colorant"#43A047",      # Green
    :road => colorant"#FB8C00",      # Orange
    :air => colorant"#8E24AA"        # Purple
)

const CONSTRAINT_COLORS = Dict(
    :passed => colorant"#4CAF50",
    :warning => colorant"#FF9800",
    :failed => colorant"#F44336"
)

const PARETO_COLORS = [
    colorant"#2196F3",
    colorant"#4CAF50",
    colorant"#FF9800",
    colorant"#9C27B0",
    colorant"#F44336"
]

# =============================================================================
# Geographic Visualization
# =============================================================================

"""
    render_route_map(routes::Vector{Route}; backend=:cairo) -> Figure

Render routes on a world map with mode-colored segments.
"""
function render_route_map(routes::Vector{Route}; backend=:cairo)
    fig = Figure(size=(1200, 800))

    # Create geographic axis
    ax = GeoAxis(
        fig[1, 1],
        dest="+proj=robin",  # Robinson projection
        title="Multi-Modal Route Visualization",
        coastlines=true
    )

    # Plot each route
    for (i, route) in enumerate(routes)
        alpha = route.pareto_rank == 1 ? 1.0 : 0.5

        for seg in route.segments
            color = get(MODE_COLORS, seg.mode, colorant"gray")

            # Draw segment as line
            lines!(ax,
                [seg.origin_lon, seg.dest_lon],
                [seg.origin_lat, seg.dest_lat],
                color=(color, alpha),
                linewidth=route.pareto_rank == 1 ? 3 : 1
            )

            # Mark endpoints
            scatter!(ax,
                [seg.origin_lon, seg.dest_lon],
                [seg.origin_lat, seg.dest_lat],
                color=color,
                markersize=8
            )
        end
    end

    # Add legend
    Legend(fig[1, 2],
        [LineElement(color=c) for c in values(MODE_COLORS)],
        collect(String.(keys(MODE_COLORS))),
        "Transport Mode"
    )

    fig
end

"""
    render_route_animation(route::Route, tracking_events::Vector{TrackingEvent})

Create animated visualization of shipment progress along route.
"""
function render_route_animation(route::Route, tracking_events::Vector{TrackingEvent})
    fig = Figure(size=(1200, 800))
    ax = GeoAxis(fig[1, 1], dest="+proj=robin", coastlines=true)

    # Static route
    for seg in route.segments
        color = get(MODE_COLORS, seg.mode, colorant"gray")
        lines!(ax,
            [seg.origin_lon, seg.dest_lon],
            [seg.origin_lat, seg.dest_lat],
            color=(color, 0.5),
            linewidth=2
        )
    end

    # Animated marker
    position = Observable(Point2f(tracking_events[1].lon, tracking_events[1].lat))
    scatter!(ax, position, color=:red, markersize=15, marker=:star5)

    # Animation loop
    record(fig, "shipment_tracking.mp4", 1:length(tracking_events); framerate=10) do i
        event = tracking_events[i]
        position[] = Point2f(event.lon, event.lat)
    end

    fig
end

# =============================================================================
# Pareto Frontier Visualization
# =============================================================================

"""
    render_pareto_frontier(points::Vector{ParetoPoint}; objectives=(:cost, :time)) -> Figure

Render 2D or 3D Pareto frontier with interactive selection.
"""
function render_pareto_frontier(points::Vector{ParetoPoint}; objectives=(:cost, :time, :carbon))
    fig = Figure(size=(1000, 800))

    if length(objectives) == 2
        ax = Axis(fig[1, 1],
            xlabel=String(objectives[1]),
            ylabel=String(objectives[2]),
            title="Pareto Frontier"
        )

        # Separate Pareto-optimal from dominated
        optimal = filter(p -> p.is_pareto_optimal, points)
        dominated = filter(p -> !p.is_pareto_optimal, points)

        # Plot dominated points
        scatter!(ax,
            [getfield(p, objectives[1]) for p in dominated],
            [getfield(p, objectives[2]) for p in dominated],
            color=(:gray, 0.5),
            markersize=10
        )

        # Plot Pareto frontier
        scatter!(ax,
            [getfield(p, objectives[1]) for p in optimal],
            [getfield(p, objectives[2]) for p in optimal],
            color=PARETO_COLORS[1],
            markersize=15
        )

        # Connect Pareto-optimal points
        sorted_optimal = sort(optimal, by=p -> getfield(p, objectives[1]))
        lines!(ax,
            [getfield(p, objectives[1]) for p in sorted_optimal],
            [getfield(p, objectives[2]) for p in sorted_optimal],
            color=PARETO_COLORS[1],
            linestyle=:dash
        )

    else  # 3D
        ax = Axis3(fig[1, 1],
            xlabel=String(objectives[1]),
            ylabel=String(objectives[2]),
            zlabel=String(objectives[3]),
            title="3D Pareto Frontier"
        )

        optimal = filter(p -> p.is_pareto_optimal, points)
        dominated = filter(p -> !p.is_pareto_optimal, points)

        scatter!(ax,
            [getfield(p, objectives[1]) for p in dominated],
            [getfield(p, objectives[2]) for p in dominated],
            [getfield(p, objectives[3]) for p in dominated],
            color=(:gray, 0.3),
            markersize=8
        )

        scatter!(ax,
            [getfield(p, objectives[1]) for p in optimal],
            [getfield(p, objectives[2]) for p in optimal],
            [getfield(p, objectives[3]) for p in optimal],
            color=PARETO_COLORS[1],
            markersize=15
        )
    end

    fig
end

# =============================================================================
# Network Graph Visualization
# =============================================================================

"""
    render_network_graph(nodes::Vector, edges::Vector) -> Figure

Visualize transport network topology with GraphMakie.
"""
function render_network_graph(nodes::Vector{String}, edges::Vector{Tuple{Int,Int,Symbol}})
    fig = Figure(size=(1200, 900))
    ax = Axis(fig[1, 1], title="Transport Network Topology")

    # Create graph
    g = SimpleDiGraph(length(nodes))
    edge_colors = Symbol[]

    for (src, dst, mode) in edges
        add_edge!(g, src, dst)
        push!(edge_colors, mode)
    end

    # Layout
    layout = GraphMakie.Spring()

    # Plot
    graphplot!(ax, g,
        layout=layout,
        nlabels=nodes,
        edge_color=[MODE_COLORS[m] for m in edge_colors],
        node_size=20,
        edge_width=2
    )

    hidedecorations!(ax)
    hidespines!(ax)

    fig
end

# =============================================================================
# Constraint Dashboard
# =============================================================================

"""
    render_constraint_dashboard(route::Route, constraints::Dict) -> Figure

Dashboard showing constraint evaluation results.
"""
function render_constraint_dashboard(route::Route, constraints::Dict)
    fig = Figure(size=(1400, 900))

    # Title
    Label(fig[0, 1:2], "Constraint Evaluation Dashboard",
        fontsize=24, halign=:center)

    # Route overview
    ax1 = Axis(fig[1, 1], title="Route Segments by Mode")
    mode_counts = Dict{Symbol, Int}()
    for seg in route.segments
        mode_counts[seg.mode] = get(mode_counts, seg.mode, 0) + 1
    end
    barplot!(ax1,
        1:length(mode_counts),
        collect(values(mode_counts)),
        color=[MODE_COLORS[m] for m in keys(mode_counts)]
    )
    ax1.xticks = (1:length(mode_counts), String.(collect(keys(mode_counts))))

    # Constraint status
    ax2 = Axis(fig[1, 2], title="Constraint Results")
    constraint_names = collect(keys(constraints))
    constraint_status = [c[:passed] ? 1 : 0 for c in values(constraints)]
    colors = [c[:passed] ? CONSTRAINT_COLORS[:passed] : CONSTRAINT_COLORS[:failed]
              for c in values(constraints)]
    barplot!(ax2, 1:length(constraints), constraint_status, color=colors)
    ax2.xticks = (1:length(constraints), constraint_names)
    ax2.yticks = ([0, 1], ["Failed", "Passed"])

    # Carbon breakdown
    ax3 = Axis(fig[2, 1], title="Carbon by Segment (kg CO₂)")
    carbon_values = [seg.carbon_kg for seg in route.segments]
    segment_labels = ["Seg $(i)" for i in 1:length(route.segments)]
    barplot!(ax3, 1:length(route.segments), carbon_values,
        color=[MODE_COLORS[seg.mode] for seg in route.segments])
    ax3.xticks = (1:length(route.segments), segment_labels)

    # Wage compliance
    ax4 = Axis(fig[2, 2], title="Wage vs Minimum (cents/hour)")
    wages = [seg.wage_cents for seg in route.segments]
    min_wage = 1260  # Example minimum
    barplot!(ax4, 1:length(route.segments), wages,
        color=[w >= min_wage ? CONSTRAINT_COLORS[:passed] : CONSTRAINT_COLORS[:failed]
               for w in wages])
    hlines!(ax4, [min_wage], color=:red, linestyle=:dash, label="Min Wage")
    ax4.xticks = (1:length(route.segments), segment_labels)

    fig
end

# =============================================================================
# Carbon Breakdown Visualization
# =============================================================================

"""
    render_carbon_breakdown(route::Route) -> Figure

Detailed carbon footprint visualization by mode and segment.
"""
function render_carbon_breakdown(route::Route)
    fig = Figure(size=(1200, 800))

    # Pie chart by mode
    ax1 = Axis(fig[1, 1], title="Carbon by Transport Mode", aspect=DataAspect())

    mode_carbon = Dict{Symbol, Float64}()
    for seg in route.segments
        mode_carbon[seg.mode] = get(mode_carbon, seg.mode, 0.0) + seg.carbon_kg
    end

    pie!(ax1,
        collect(values(mode_carbon)),
        color=[MODE_COLORS[m] for m in keys(mode_carbon)]
    )
    hidedecorations!(ax1)

    Legend(fig[1, 2],
        [PolyElement(color=MODE_COLORS[m]) for m in keys(mode_carbon)],
        ["$(m): $(round(c, digits=1)) kg" for (m, c) in mode_carbon],
        "Mode"
    )

    # Cumulative carbon along route
    ax2 = Axis(fig[2, 1:2],
        xlabel="Route Progress",
        ylabel="Cumulative CO₂ (kg)",
        title="Carbon Accumulation Along Route"
    )

    cumulative = cumsum([seg.carbon_kg for seg in route.segments])
    lines!(ax2, 0:length(cumulative), [0; cumulative],
        color=:green, linewidth=3)
    scatter!(ax2, 1:length(cumulative), cumulative,
        color=[MODE_COLORS[seg.mode] for seg in route.segments],
        markersize=15)

    # Budget line
    budget = route.total_carbon * 0.8  # Example budget
    hlines!(ax2, [budget], color=:red, linestyle=:dash,
        label="Carbon Budget")

    fig
end

# =============================================================================
# Real-time Tracking
# =============================================================================

"""
    subscribe_tracking_updates(redis_conn, channel::String, callback::Function)

Subscribe to real-time tracking updates from Dragonfly.
"""
function subscribe_tracking_updates(redis_conn, channel::String, callback::Function)
    Redis.subscribe(redis_conn, channel) do msg
        event = JSON3.read(msg, TrackingEvent)
        callback(event)
    end
end

# =============================================================================
# Web Application
# =============================================================================

"""VEDS Visualization Application"""
mutable struct VEDSApp
    server::Union{Nothing, HTTP.Server}
    redis_conn::Union{Nothing, Redis.RedisConnection}
    tracking_observable::Observable{Vector{TrackingEvent}}
end

VEDSApp() = VEDSApp(nothing, nothing, Observable(TrackingEvent[]))

"""
    start_server(app::VEDSApp; port=8080)

Start the Genie web server for interactive visualization.
"""
function start_server(app::VEDSApp; port=8080)
    Genie.config.server_port = port

    # Routes
    route("/") do
        """
        <!DOCTYPE html>
        <html>
        <head><title>VEDS Visualization</title></head>
        <body>
            <h1>VEDS Visualization Dashboard</h1>
            <ul>
                <li><a href="/routes">Route Map</a></li>
                <li><a href="/pareto">Pareto Frontier</a></li>
                <li><a href="/network">Network Graph</a></li>
                <li><a href="/constraints">Constraint Dashboard</a></li>
                <li><a href="/carbon">Carbon Analysis</a></li>
            </ul>
        </body>
        </html>
        """
    end

    route("/api/routes") do
        # Fetch routes from API
        JSON3.write(Route[])
    end

    route("/api/tracking/subscribe") do
        # WebSocket endpoint for real-time updates
        # Implementation would use Genie's WebSocket support
    end

    up(async=true)
    @info "VEDS Visualization server started on port $port"
end

"""
    stop_server(app::VEDSApp)

Stop the web server.
"""
function stop_server(app::VEDSApp)
    down()
    @info "VEDS Visualization server stopped"
end

# =============================================================================
# Utility Functions
# =============================================================================

"""Calculate great circle distance between two points"""
function haversine_distance(lat1, lon1, lat2, lon2)
    R = 6371.0  # Earth radius in km

    φ1 = deg2rad(lat1)
    φ2 = deg2rad(lat2)
    Δφ = deg2rad(lat2 - lat1)
    Δλ = deg2rad(lon2 - lon1)

    a = sin(Δφ/2)^2 + cos(φ1) * cos(φ2) * sin(Δλ/2)^2
    c = 2 * atan(sqrt(a), sqrt(1-a))

    R * c
end

"""Generate sample data for testing"""
function generate_sample_route()
    Route(
        "route-001",
        [
            Segment("seg-1", 31.2304, 121.4737, 22.3193, 114.1694, :maritime, "COSCO", 2500.0, 48.0, 850.0, 1500),
            Segment("seg-2", 22.3193, 114.1694, 1.3521, 103.8198, :maritime, "COSCO", 1800.0, 72.0, 1200.0, 1500),
            Segment("seg-3", 1.3521, 103.8198, 51.9225, 4.4792, :maritime, "Maersk", 4500.0, 336.0, 3200.0, 1800),
            Segment("seg-4", 51.9225, 4.4792, 51.5074, -0.1278, :rail, "DB Cargo", 450.0, 8.0, 45.0, 2200)
        ],
        9250.0,
        464.0,
        5295.0,
        1,
        String[]
    )
end

end # module

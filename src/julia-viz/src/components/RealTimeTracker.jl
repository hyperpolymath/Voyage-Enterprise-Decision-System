"""
Real-Time Tracking Visualization

Live shipment tracking with animated updates:
- Position streaming via Dragonfly/Redis
- Animated markers on map
- ETA predictions
- Event timeline
"""
module RealTimeTracker

using CairoMakie
using GeoMakie
using Dates
using Observables

export TrackingState, update_position!, render_tracking_dashboard
export connect_dragonfly, subscribe_events

# =============================================================================
# Data Types
# =============================================================================

"""Current state of a tracked shipment"""
mutable struct ShipmentState
    shipment_id::String
    current_lat::Float64
    current_lon::Float64
    heading::Float64  # degrees from north
    speed_knots::Float64
    status::Symbol  # :in_transit, :at_port, :delayed, :arrived
    carrier::String
    vessel_name::String
    eta::DateTime
    origin::String
    destination::String
    cargo_description::String
    last_update::DateTime
end

"""Tracking event record"""
struct TrackingEvent
    timestamp::DateTime
    event_type::Symbol  # :position, :status_change, :eta_update, :alert
    lat::Float64
    lon::Float64
    data::Dict{String, Any}
end

"""Collection of tracked shipments"""
mutable struct TrackingState
    shipments::Dict{String, ShipmentState}
    event_history::Dict{String, Vector{TrackingEvent}}
    position_observables::Dict{String, Observable{Point2f}}
    status_observables::Dict{String, Observable{Symbol}}
end

TrackingState() = TrackingState(
    Dict{String, ShipmentState}(),
    Dict{String, Vector{TrackingEvent}}(),
    Dict{String, Observable{Point2f}}(),
    Dict{String, Observable{Symbol}}()
)

# =============================================================================
# Status Colors and Icons
# =============================================================================

const STATUS_STYLES = Dict(
    :in_transit => (color=colorant"#4CAF50", marker=:circle),
    :at_port => (color=colorant"#2196F3", marker=:rect),
    :delayed => (color=colorant"#FF9800", marker=:diamond),
    :arrived => (color=colorant"#9C27B0", marker=:star5),
    :alert => (color=colorant"#F44336", marker=:xcross)
)

# =============================================================================
# State Management
# =============================================================================

"""Add or update a shipment in tracking state"""
function update_position!(state::TrackingState, shipment_id::String,
    lat::Float64, lon::Float64;
    heading=0.0, speed=0.0, status=:in_transit
)
    if haskey(state.shipments, shipment_id)
        ship = state.shipments[shipment_id]
        ship.current_lat = lat
        ship.current_lon = lon
        ship.heading = heading
        ship.speed_knots = speed
        ship.status = status
        ship.last_update = now()
    end

    # Update observables for reactive rendering
    if haskey(state.position_observables, shipment_id)
        state.position_observables[shipment_id][] = Point2f(lon, lat)
    end

    if haskey(state.status_observables, shipment_id)
        state.status_observables[shipment_id][] = status
    end

    # Record event
    if !haskey(state.event_history, shipment_id)
        state.event_history[shipment_id] = TrackingEvent[]
    end
    push!(state.event_history[shipment_id], TrackingEvent(
        now(), :position, lat, lon,
        Dict("heading" => heading, "speed" => speed)
    ))
end

"""Register a new shipment for tracking"""
function register_shipment!(state::TrackingState, shipment::ShipmentState)
    state.shipments[shipment.shipment_id] = shipment
    state.position_observables[shipment.shipment_id] =
        Observable(Point2f(shipment.current_lon, shipment.current_lat))
    state.status_observables[shipment.shipment_id] =
        Observable(shipment.status)
    state.event_history[shipment.shipment_id] = TrackingEvent[]
end

# =============================================================================
# Live Dashboard
# =============================================================================

"""
    render_tracking_dashboard(state::TrackingState) -> Figure

Create real-time tracking dashboard with map and details.
"""
function render_tracking_dashboard(state::TrackingState;
    size=(1600, 900),
    projection="+proj=merc"
)
    fig = Figure(size=size)

    # Map view (main panel)
    ax_map = GeoAxis(fig[1:2, 1],
        dest=projection,
        coastlines=true,
        title="Live Shipment Tracking"
    )

    # Plot each shipment with reactive position
    for (id, ship) in state.shipments
        pos_obs = state.position_observables[id]
        status_obs = state.status_observables[id]

        # Reactive marker
        marker_color = @lift begin
            STATUS_STYLES[$status_obs].color
        end

        scatter!(ax_map, pos_obs,
            color=marker_color,
            markersize=20,
            marker=:circle
        )

        # Trail (last N positions)
        if haskey(state.event_history, id)
            events = state.event_history[id]
            if length(events) > 1
                trail_lons = [e.lon for e in events[max(1, end-20):end]]
                trail_lats = [e.lat for e in events[max(1, end-20):end]]
                lines!(ax_map, trail_lons, trail_lats,
                    color=(:gray, 0.5), linewidth=1)
            end
        end
    end

    # Shipment list panel
    ax_list = Axis(fig[1, 2], title="Active Shipments")
    hidedecorations!(ax_list)
    hidespines!(ax_list)

    y_pos = 1.0
    for (id, ship) in state.shipments
        style = STATUS_STYLES[ship.status]
        text!(ax_list, 0.1, y_pos,
            text="$(ship.shipment_id)",
            fontsize=12, align=(:left, :center))
        text!(ax_list, 0.5, y_pos,
            text="$(ship.vessel_name)",
            fontsize=10, align=(:left, :center), color=:gray)
        scatter!(ax_list, [0.9], [y_pos],
            color=style.color, markersize=10, marker=style.marker)
        y_pos -= 0.1
    end
    ylims!(ax_list, 0, 1.1)
    xlims!(ax_list, 0, 1)

    # ETA panel
    ax_eta = Axis(fig[2, 2], title="Estimated Arrivals")
    hidedecorations!(ax_eta)
    hidespines!(ax_eta)

    y_pos = 1.0
    for (id, ship) in state.shipments
        hours_to_eta = Dates.value(ship.eta - now()) / (1000 * 60 * 60)
        eta_str = Dates.format(ship.eta, "yyyy-mm-dd HH:MM")

        color = hours_to_eta < 0 ? :red :
                hours_to_eta < 24 ? :orange : :green

        text!(ax_eta, 0.1, y_pos,
            text="$(ship.shipment_id) → $(ship.destination)",
            fontsize=10, align=(:left, :center))
        text!(ax_eta, 0.7, y_pos,
            text=eta_str,
            fontsize=10, align=(:left, :center), color=color)
        y_pos -= 0.15
    end
    ylims!(ax_eta, 0, 1.1)
    xlims!(ax_eta, 0, 1)

    # Legend
    Legend(fig[3, 1:2],
        [MarkerElement(color=s.color, marker=s.marker, markersize=15)
         for s in values(STATUS_STYLES)],
        String.(keys(STATUS_STYLES)),
        "Status",
        orientation=:horizontal,
        tellwidth=false
    )

    fig
end

# =============================================================================
# Event Timeline
# =============================================================================

"""
    render_event_timeline(events::Vector{TrackingEvent}) -> Figure

Render timeline of tracking events for a shipment.
"""
function render_event_timeline(events::Vector{TrackingEvent};
    size=(1200, 400)
)
    fig = Figure(size=size)

    ax = Axis(fig[1, 1],
        title="Shipment Event Timeline",
        xlabel="Time",
        ylabel="Event Type"
    )

    event_types = unique(e.event_type for e in events)
    type_y = Dict(t => i for (i, t) in enumerate(event_types))

    colors = Dict(
        :position => :blue,
        :status_change => :orange,
        :eta_update => :green,
        :alert => :red
    )

    times = 1:length(events)

    for (i, event) in enumerate(events)
        y = type_y[event.event_type]
        c = get(colors, event.event_type, :gray)

        scatter!(ax, [i], [y], color=c, markersize=10)

        if event.event_type == :alert
            text!(ax, i, y + 0.3,
                text="⚠",
                fontsize=14, align=(:center, :bottom))
        end
    end

    ax.yticks = (1:length(event_types), String.(event_types))

    # Time labels
    tick_idx = 1:max(1, length(events)÷10):length(events)
    ax.xticks = (collect(tick_idx),
        [Dates.format(events[i].timestamp, "HH:MM") for i in tick_idx])

    fig
end

# =============================================================================
# Dragonfly/Redis Integration
# =============================================================================

"""Connect to Dragonfly for real-time updates"""
function connect_dragonfly(host::String, port::Int; password=nothing)
    # Placeholder - actual implementation would use Redis.jl
    @info "Connecting to Dragonfly at $host:$port"
    # return Redis.RedisConnection(host=host, port=port, password=password)
    nothing
end

"""Subscribe to tracking event stream"""
function subscribe_events(conn, channel::String, state::TrackingState)
    @info "Subscribing to tracking channel: $channel"
    # Placeholder - actual implementation would use Redis pub/sub
    # Redis.subscribe(conn, channel) do msg
    #     event = JSON3.read(msg, TrackingEvent)
    #     update_position!(state, event.shipment_id, event.lat, event.lon)
    # end
end

# =============================================================================
# Sample Data
# =============================================================================

"""Generate sample tracking state"""
function sample_tracking_state()
    state = TrackingState()

    # Add sample shipments
    register_shipment!(state, ShipmentState(
        "SHIP-001",
        5.5, 45.2,  # Bay of Biscay
        270.0, 18.5,
        :in_transit,
        "Maersk",
        "Emma Maersk",
        now() + Day(2),
        "Shanghai",
        "Rotterdam",
        "Electronics",
        now()
    ))

    register_shipment!(state, ShipmentState(
        "SHIP-002",
        12.5, 72.8,  # Indian Ocean
        285.0, 16.2,
        :in_transit,
        "COSCO",
        "COSCO Shipping Universe",
        now() + Day(7),
        "Shanghai",
        "Hamburg",
        "Machinery",
        now()
    ))

    register_shipment!(state, ShipmentState(
        "SHIP-003",
        51.9, 4.5,  # Rotterdam
        0.0, 0.0,
        :at_port,
        "Hapag-Lloyd",
        "Colombo Express",
        now(),
        "Singapore",
        "Rotterdam",
        "Consumer Goods",
        now()
    ))

    state
end

end # module

"""
Geographic Map Components for VEDS

Provides reusable components for geographic visualization:
- World map with shipping lanes
- Port markers
- Route overlays
- Tracking position indicators
"""
module GeoMap

using GeoMakie
using CairoMakie
using Colors

export create_world_map, add_ports, add_shipping_lanes, add_route_overlay

# =============================================================================
# Map Creation
# =============================================================================

"""
    create_world_map(; projection="+proj=robin", bounds=nothing) -> Figure, GeoAxis

Create a base world map with optional projection and bounds.

Projections:
- "+proj=robin" - Robinson (balanced)
- "+proj=merc" - Mercator (shipping standard)
- "+proj=ortho +lat_0=45 +lon_0=0" - Orthographic (globe view)
"""
function create_world_map(;
    projection="+proj=robin",
    bounds=nothing,
    size=(1400, 800)
)
    fig = Figure(size=size, backgroundcolor=:white)

    ax = GeoAxis(
        fig[1, 1],
        dest=projection,
        coastlines=true,
        coastlines_color=:gray60,
        lonlims=bounds !== nothing ? bounds[1:2] : automatic,
        latlims=bounds !== nothing ? bounds[3:4] : automatic
    )

    # Ocean background
    # poly!(ax, GeoMakie.land(), color=(:gray90, 0.5))

    fig, ax
end

# =============================================================================
# Port Visualization
# =============================================================================

"""Port data structure"""
struct Port
    name::String
    lat::Float64
    lon::Float64
    port_type::Symbol  # :major, :minor, :hub
    capacity_teu::Int
end

const PORT_SIZES = Dict(
    :major => 20,
    :hub => 25,
    :minor => 12
)

const PORT_COLORS = Dict(
    :major => colorant"#1976D2",
    :hub => colorant"#D32F2F",
    :minor => colorant"#388E3C"
)

"""
    add_ports(ax::GeoAxis, ports::Vector{Port})

Add port markers to the map.
"""
function add_ports(ax, ports::Vector{Port})
    for port in ports
        scatter!(ax,
            [port.lon], [port.lat],
            color=PORT_COLORS[port.port_type],
            markersize=PORT_SIZES[port.port_type],
            marker=:circle,
            strokewidth=2,
            strokecolor=:white
        )

        # Port label
        text!(ax,
            port.lon, port.lat + 2,
            text=port.name,
            fontsize=10,
            align=(:center, :bottom)
        )
    end
end

# =============================================================================
# Shipping Lanes
# =============================================================================

"""Major shipping lane"""
struct ShippingLane
    name::String
    waypoints::Vector{Tuple{Float64, Float64}}  # (lon, lat) pairs
    traffic_level::Symbol  # :high, :medium, :low
end

const LANE_WIDTHS = Dict(
    :high => 4,
    :medium => 2,
    :low => 1
)

const LANE_COLORS = Dict(
    :high => colorant"#0D47A1",
    :medium => colorant"#1565C0",
    :low => colorant"#42A5F5"
)

"""
    add_shipping_lanes(ax::GeoAxis, lanes::Vector{ShippingLane})

Overlay major shipping lanes on the map.
"""
function add_shipping_lanes(ax, lanes::Vector{ShippingLane})
    for lane in lanes
        lons = [wp[1] for wp in lane.waypoints]
        lats = [wp[2] for wp in lane.waypoints]

        lines!(ax,
            lons, lats,
            color=(LANE_COLORS[lane.traffic_level], 0.6),
            linewidth=LANE_WIDTHS[lane.traffic_level],
            linestyle=:solid
        )
    end
end

# =============================================================================
# Route Overlay
# =============================================================================

const MODE_STYLES = Dict(
    :maritime => (color=colorant"#1E88E5", style=:solid, width=3),
    :rail => (color=colorant"#43A047", style=:solid, width=2),
    :road => (color=colorant"#FB8C00", style=:dot, width=2),
    :air => (color=colorant"#8E24AA", style=:dash, width=2)
)

"""
    add_route_overlay(ax::GeoAxis, segments::Vector; highlight_violations=true)

Overlay route segments with mode-specific styling.
"""
function add_route_overlay(ax, segments::Vector; highlight_violations=true)
    for seg in segments
        style = get(MODE_STYLES, seg.mode, (color=:gray, style=:solid, width=1))

        # Check for violations
        is_violated = !isempty(seg.violations) && highlight_violations

        lines!(ax,
            [seg.origin_lon, seg.dest_lon],
            [seg.origin_lat, seg.dest_lat],
            color=is_violated ? colorant"#F44336" : style.color,
            linestyle=style.style,
            linewidth=is_violated ? style.width + 2 : style.width
        )

        # Direction arrow at midpoint
        mid_lon = (seg.origin_lon + seg.dest_lon) / 2
        mid_lat = (seg.origin_lat + seg.dest_lat) / 2

        scatter!(ax,
            [mid_lon], [mid_lat],
            color=style.color,
            marker=:rtriangle,
            markersize=8,
            rotations=[atan(seg.dest_lat - seg.origin_lat, seg.dest_lon - seg.origin_lon)]
        )
    end
end

# =============================================================================
# Sample Data
# =============================================================================

"""Generate sample ports along Shanghai-Rotterdam corridor"""
function sample_ports()
    [
        Port("Shanghai", 31.2304, 121.4737, :hub, 47000000),
        Port("Hong Kong", 22.3193, 114.1694, :major, 19800000),
        Port("Singapore", 1.3521, 103.8198, :hub, 37200000),
        Port("Colombo", 6.9271, 79.8612, :minor, 7200000),
        Port("Suez", 29.9668, 32.5498, :major, 5000000),
        Port("Piraeus", 37.9474, 23.6383, :major, 5650000),
        Port("Rotterdam", 51.9225, 4.4792, :hub, 14500000),
        Port("Hamburg", 53.5511, 9.9937, :major, 8700000),
        Port("London Gateway", 51.5074, -0.1278, :major, 1600000),
    ]
end

"""Generate major shipping lanes"""
function sample_shipping_lanes()
    [
        ShippingLane("Asia-Europe via Suez", [
            (121.4737, 31.2304),   # Shanghai
            (114.1694, 22.3193),   # Hong Kong
            (103.8198, 1.3521),    # Singapore
            (79.8612, 6.9271),     # Colombo
            (32.5498, 29.9668),    # Suez
            (23.6383, 37.9474),    # Piraeus
            (4.4792, 51.9225),     # Rotterdam
        ], :high),

        ShippingLane("Intra-Asia", [
            (121.4737, 31.2304),   # Shanghai
            (129.0756, 35.1796),   # Busan
            (139.6917, 35.6895),   # Tokyo
        ], :medium),
    ]
end

end # module

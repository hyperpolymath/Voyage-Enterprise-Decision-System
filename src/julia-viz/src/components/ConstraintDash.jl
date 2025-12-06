"""
Constraint Dashboard Components

Real-time constraint monitoring and violation visualization:
- Constraint status gauges
- Violation heatmaps
- Temporal violation trends
- Compliance scorecards
"""
module ConstraintDash

using CairoMakie
using Colors
using Dates

export plot_constraint_gauges, plot_violation_heatmap
export plot_compliance_timeline, plot_constraint_scorecard

# =============================================================================
# Data Types
# =============================================================================

"""Constraint evaluation result"""
struct ConstraintResult
    constraint_id::String
    name::String
    category::Symbol  # :wage, :carbon, :time, :safety, :sanction
    is_hard::Bool
    passed::Bool
    actual_value::Float64
    threshold_value::Float64
    violation_severity::Float64  # 0.0 to 1.0
    details::String
end

"""Constraint categories with colors"""
const CATEGORY_COLORS = Dict(
    :wage => colorant"#4CAF50",     # Green - labor
    :carbon => colorant"#2196F3",   # Blue - environment
    :time => colorant"#FF9800",     # Orange - operations
    :safety => colorant"#F44336",   # Red - critical
    :sanction => colorant"#9C27B0"  # Purple - compliance
)

const STATUS_COLORS = Dict(
    :passed => colorant"#4CAF50",
    :warning => colorant"#FF9800",
    :failed => colorant"#F44336"
)

# =============================================================================
# Gauge Visualization
# =============================================================================

"""
    plot_constraint_gauges(results::Vector{ConstraintResult}) -> Figure

Create gauge-style visualization for each constraint.
"""
function plot_constraint_gauges(results::Vector{ConstraintResult};
    size=(1200, 400),
    cols=4
)
    n = length(results)
    rows = ceil(Int, n / cols)

    fig = Figure(size=(size[1], size[2] * rows ÷ 2))

    for (idx, result) in enumerate(results)
        row = (idx - 1) ÷ cols + 1
        col = (idx - 1) % cols + 1

        ax = Axis(fig[row, col],
            title=result.name,
            aspect=DataAspect()
        )
        hidedecorations!(ax)
        hidespines!(ax)

        # Draw gauge arc
        n_segments = 50
        angles = range(π, 2π, length=n_segments)

        # Background arc (gray)
        for i in 1:(n_segments-1)
            θ1, θ2 = angles[i], angles[i+1]
            poly!(ax,
                Point2f[(0, 0), (cos(θ1), sin(θ1)), (cos(θ2), sin(θ2))],
                color=:gray90
            )
        end

        # Value arc
        if result.threshold_value > 0
            fill_ratio = clamp(result.actual_value / result.threshold_value, 0, 1.5)
        else
            fill_ratio = result.passed ? 0.5 : 1.0
        end

        fill_segments = round(Int, fill_ratio * n_segments)
        fill_segments = min(fill_segments, n_segments - 1)

        color = if result.passed
            STATUS_COLORS[:passed]
        elseif result.violation_severity < 0.5
            STATUS_COLORS[:warning]
        else
            STATUS_COLORS[:failed]
        end

        for i in 1:fill_segments
            θ1, θ2 = angles[i], angles[i+1]
            poly!(ax,
                Point2f[(0, 0), (0.8*cos(θ1), 0.8*sin(θ1)), (0.8*cos(θ2), 0.8*sin(θ2))],
                color=color
            )
        end

        # Center text
        text!(ax, 0, -0.2,
            text=result.passed ? "PASS" : "FAIL",
            fontsize=14,
            align=(:center, :center),
            color=color
        )

        # Value text
        text!(ax, 0, -0.5,
            text="$(round(result.actual_value, digits=1)) / $(round(result.threshold_value, digits=1))",
            fontsize=10,
            align=(:center, :center)
        )

        # Category indicator
        scatter!(ax, [0], [0.3],
            color=CATEGORY_COLORS[result.category],
            markersize=8
        )

        xlims!(ax, -1.5, 1.5)
        ylims!(ax, -0.8, 0.6)
    end

    fig
end

# =============================================================================
# Violation Heatmap
# =============================================================================

"""
    plot_violation_heatmap(routes::Vector{String}, constraints::Vector{String}, violations::Matrix{Float64})

Create heatmap showing violation severity across routes and constraints.
"""
function plot_violation_heatmap(
    routes::Vector{String},
    constraints::Vector{String},
    violations::Matrix{Float64};  # routes × constraints
    size=(1000, 800)
)
    fig = Figure(size=size)

    ax = Axis(fig[1, 1],
        title="Constraint Violations by Route",
        xlabel="Constraints",
        ylabel="Routes",
        xticks=(1:length(constraints), constraints),
        yticks=(1:length(routes), routes),
        xticklabelrotation=π/4
    )

    # Custom colormap: green -> yellow -> red
    cmap = cgrad([:green, :yellow, :red])

    hm = heatmap!(ax, violations, colormap=cmap, colorrange=(0, 1))

    Colorbar(fig[1, 2], hm, label="Violation Severity")

    # Add pass/fail annotations
    for i in 1:length(routes)
        for j in 1:length(constraints)
            val = violations[i, j]
            text!(ax, j, i,
                text=val == 0 ? "✓" : "✗",
                align=(:center, :center),
                color=val == 0 ? :darkgreen : :darkred,
                fontsize=12
            )
        end
    end

    fig
end

# =============================================================================
# Compliance Timeline
# =============================================================================

"""
    plot_compliance_timeline(timestamps::Vector{DateTime}, compliance_scores::Vector{Float64})

Show compliance score over time with trend analysis.
"""
function plot_compliance_timeline(
    timestamps::Vector{DateTime},
    compliance_scores::Vector{Float64};
    size=(1000, 500),
    threshold=0.8
)
    fig = Figure(size=size)

    ax = Axis(fig[1, 1],
        title="Compliance Score Over Time",
        xlabel="Time",
        ylabel="Compliance Score"
    )

    # Time values for plotting
    time_vals = 1:length(timestamps)

    # Compliance line
    lines!(ax, time_vals, compliance_scores,
        color=:dodgerblue, linewidth=2, label="Compliance")

    # Threshold line
    hlines!(ax, [threshold],
        color=:red, linestyle=:dash, linewidth=2, label="Target")

    # Fill below threshold
    band!(ax, time_vals, fill(0.0, length(time_vals)), compliance_scores,
        color=(:dodgerblue, 0.2))

    # Mark violations
    violation_idx = findall(s -> s < threshold, compliance_scores)
    if !isempty(violation_idx)
        scatter!(ax, violation_idx, compliance_scores[violation_idx],
            color=:red, markersize=10, marker=:xcross,
            label="Below Target")
    end

    # Moving average trend
    window = min(7, length(compliance_scores))
    if window > 1
        ma = [mean(compliance_scores[max(1, i-window+1):i]) for i in 1:length(compliance_scores)]
        lines!(ax, time_vals, ma,
            color=:orange, linewidth=2, linestyle=:dot,
            label="7-day MA")
    end

    # X-axis labels
    tick_positions = 1:max(1, length(timestamps)÷10):length(timestamps)
    ax.xticks = (collect(tick_positions),
        [Dates.format(timestamps[i], "mm-dd") for i in tick_positions])

    axislegend(ax, position=:lb)

    ylims!(ax, 0, 1.1)

    fig
end

# =============================================================================
# Constraint Scorecard
# =============================================================================

"""
    plot_constraint_scorecard(results::Vector{ConstraintResult})

Executive summary scorecard with category breakdown.
"""
function plot_constraint_scorecard(results::Vector{ConstraintResult};
    size=(1200, 800)
)
    fig = Figure(size=size)

    # Title
    Label(fig[0, 1:3], "Constraint Compliance Scorecard",
        fontsize=24, halign=:center, tellwidth=false)

    # Overall score
    total = length(results)
    passed = count(r -> r.passed, results)
    score = passed / total

    ax1 = Axis(fig[1, 1], title="Overall Score", aspect=DataAspect())
    hidedecorations!(ax1)
    hidespines!(ax1)

    # Large circular gauge
    n_seg = 100
    angles = range(0, 2π, length=n_seg+1)
    for i in 1:n_seg
        θ1, θ2 = angles[i], angles[i+1]
        progress = i / n_seg
        c = progress <= score ? colorant"#4CAF50" : colorant"#E0E0E0"
        poly!(ax1,
            Point2f[(0, 0), (cos(θ1), sin(θ1)), (cos(θ2), sin(θ2))],
            color=c
        )
    end
    poly!(ax1, decompose(Point2f, Circle(Point2f(0, 0), 0.6f0)), color=:white)
    text!(ax1, 0, 0,
        text="$(round(Int, score * 100))%",
        fontsize=30,
        align=(:center, :center)
    )
    text!(ax1, 0, -0.3,
        text="$passed / $total passed",
        fontsize=12,
        align=(:center, :center)
    )

    # Category breakdown
    ax2 = Axis(fig[1, 2], title="By Category")

    categories = unique(r.category for r in results)
    cat_scores = Float64[]
    cat_colors = []

    for cat in categories
        cat_results = filter(r -> r.category == cat, results)
        cat_passed = count(r -> r.passed, cat_results)
        push!(cat_scores, cat_passed / length(cat_results))
        push!(cat_colors, CATEGORY_COLORS[cat])
    end

    barplot!(ax2, 1:length(categories), cat_scores,
        color=cat_colors,
        direction=:x)
    ax2.yticks = (1:length(categories), String.(categories))
    ax2.xlabel = "Pass Rate"
    xlims!(ax2, 0, 1.1)

    # Hard vs Soft constraints
    ax3 = Axis(fig[1, 3], title="Hard vs Soft Constraints")

    hard = filter(r -> r.is_hard, results)
    soft = filter(r -> !r.is_hard, results)

    hard_passed = count(r -> r.passed, hard)
    soft_passed = count(r -> r.passed, soft)

    barplot!(ax3, [1, 2],
        [hard_passed / max(1, length(hard)), soft_passed / max(1, length(soft))],
        color=[:red, :blue])
    ax3.xticks = ([1, 2], ["Hard", "Soft"])
    ax3.ylabel = "Pass Rate"
    ylims!(ax3, 0, 1.1)

    # Violation details table
    violations = filter(r -> !r.passed, results)
    if !isempty(violations)
        Label(fig[2, 1:3], "Violations Requiring Attention",
            fontsize=18, halign=:center, tellwidth=false)

        for (i, v) in enumerate(violations[1:min(5, length(violations))])
            severity_color = v.violation_severity > 0.7 ? :red :
                            v.violation_severity > 0.3 ? :orange : :yellow
            Label(fig[2+i, 1],
                "$(v.name) [$(v.category)]",
                fontsize=12, halign=:left)
            Label(fig[2+i, 2],
                "$(round(v.actual_value, digits=1)) vs $(round(v.threshold_value, digits=1))",
                fontsize=12, halign=:center)
            Label(fig[2+i, 3],
                v.is_hard ? "HARD - BLOCKING" : "SOFT - WARNING",
                fontsize=12, halign=:right, color=v.is_hard ? :red : :orange)
        end
    end

    fig
end

# =============================================================================
# Sample Data
# =============================================================================

"""Generate sample constraint results"""
function sample_constraint_results()
    [
        ConstraintResult("c1", "ILO Minimum Wage (DE)", :wage, true, true, 1450.0, 1260.0, 0.0, "Above minimum"),
        ConstraintResult("c2", "ILO Minimum Wage (NL)", :wage, true, false, 1100.0, 1260.0, 0.7, "Below minimum by 160"),
        ConstraintResult("c3", "Carbon Budget 2030", :carbon, false, true, 4200.0, 5000.0, 0.0, "Within budget"),
        ConstraintResult("c4", "EU Working Time", :time, true, true, 42.0, 48.0, 0.0, "Compliant"),
        ConstraintResult("c5", "OFAC Sanctions", :sanction, true, true, 0.0, 0.0, 0.0, "No sanctioned entities"),
        ConstraintResult("c6", "Route Safety Score", :safety, true, true, 0.85, 0.7, 0.0, "Above threshold"),
        ConstraintResult("c7", "Night Driving Limit", :safety, false, false, 6.0, 4.0, 0.5, "Exceeded by 2 hours"),
        ConstraintResult("c8", "Carbon per Tonne-km", :carbon, false, true, 0.042, 0.05, 0.0, "Efficient"),
    ]
end

end # module

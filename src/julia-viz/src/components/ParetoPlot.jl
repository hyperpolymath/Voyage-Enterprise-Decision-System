"""
Pareto Frontier Visualization Components

Interactive multi-objective optimization visualization:
- 2D/3D Pareto frontiers
- Trade-off analysis
- Solution comparison
- Sensitivity surfaces
"""
module ParetoPlot

using CairoMakie
using Colors
using Statistics

export plot_pareto_2d, plot_pareto_3d, plot_tradeoff_matrix, plot_radar_comparison

# =============================================================================
# Data Types
# =============================================================================

"""Solution point in objective space"""
struct Solution
    id::String
    objectives::Dict{Symbol, Float64}
    is_pareto_optimal::Bool
    metadata::Dict{Symbol, Any}
end

# =============================================================================
# 2D Pareto Frontier
# =============================================================================

"""
    plot_pareto_2d(solutions::Vector{Solution}, x_obj::Symbol, y_obj::Symbol) -> Figure

Create 2D Pareto frontier plot with interactive hover.
"""
function plot_pareto_2d(solutions::Vector{Solution}, x_obj::Symbol, y_obj::Symbol;
    size=(900, 700),
    show_dominated=true,
    highlight_best=true
)
    fig = Figure(size=size)

    ax = Axis(fig[1, 1],
        xlabel=String(x_obj),
        ylabel=String(y_obj),
        title="Pareto Frontier: $(x_obj) vs $(y_obj)"
    )

    optimal = filter(s -> s.is_pareto_optimal, solutions)
    dominated = filter(s -> !s.is_pareto_optimal, solutions)

    # Plot dominated points
    if show_dominated && !isempty(dominated)
        scatter!(ax,
            [s.objectives[x_obj] for s in dominated],
            [s.objectives[y_obj] for s in dominated],
            color=(:gray, 0.4),
            markersize=8,
            label="Dominated"
        )
    end

    # Plot Pareto-optimal points
    if !isempty(optimal)
        x_vals = [s.objectives[x_obj] for s in optimal]
        y_vals = [s.objectives[y_obj] for s in optimal]

        # Sort by x for frontier line
        perm = sortperm(x_vals)

        scatter!(ax,
            x_vals,
            y_vals,
            color=:dodgerblue,
            markersize=15,
            label="Pareto Optimal"
        )

        # Frontier line
        lines!(ax,
            x_vals[perm],
            y_vals[perm],
            color=:dodgerblue,
            linestyle=:dash,
            linewidth=2
        )

        # Highlight extremes
        if highlight_best
            x_min_idx = argmin(x_vals)
            y_min_idx = argmin(y_vals)

            scatter!(ax, [x_vals[x_min_idx]], [y_vals[x_min_idx]],
                color=:green, markersize=20, marker=:star5)
            scatter!(ax, [x_vals[y_min_idx]], [y_vals[y_min_idx]],
                color=:orange, markersize=20, marker=:star5)
        end
    end

    # Utopia point (ideal but unachievable)
    if !isempty(optimal)
        utopia_x = minimum(s.objectives[x_obj] for s in optimal)
        utopia_y = minimum(s.objectives[y_obj] for s in optimal)
        scatter!(ax, [utopia_x], [utopia_y],
            color=(:red, 0.5), markersize=25, marker=:diamond,
            label="Utopia Point")
    end

    axislegend(ax, position=:rt)

    fig
end

# =============================================================================
# 3D Pareto Frontier
# =============================================================================

"""
    plot_pareto_3d(solutions::Vector{Solution}, x_obj::Symbol, y_obj::Symbol, z_obj::Symbol)

Create 3D Pareto surface visualization.
"""
function plot_pareto_3d(solutions::Vector{Solution},
    x_obj::Symbol, y_obj::Symbol, z_obj::Symbol;
    size=(1000, 800)
)
    fig = Figure(size=size)

    ax = Axis3(fig[1, 1],
        xlabel=String(x_obj),
        ylabel=String(y_obj),
        zlabel=String(z_obj),
        title="3D Pareto Frontier",
        azimuth=0.5π
    )

    optimal = filter(s -> s.is_pareto_optimal, solutions)
    dominated = filter(s -> !s.is_pareto_optimal, solutions)

    # Dominated (transparent)
    if !isempty(dominated)
        scatter!(ax,
            [s.objectives[x_obj] for s in dominated],
            [s.objectives[y_obj] for s in dominated],
            [s.objectives[z_obj] for s in dominated],
            color=(:gray, 0.2),
            markersize=6
        )
    end

    # Pareto surface
    if !isempty(optimal)
        scatter!(ax,
            [s.objectives[x_obj] for s in optimal],
            [s.objectives[y_obj] for s in optimal],
            [s.objectives[z_obj] for s in optimal],
            color=:dodgerblue,
            markersize=12
        )
    end

    fig
end

# =============================================================================
# Trade-off Matrix
# =============================================================================

"""
    plot_tradeoff_matrix(solutions::Vector{Solution}, objectives::Vector{Symbol})

Create scatter plot matrix showing all pairwise trade-offs.
"""
function plot_tradeoff_matrix(solutions::Vector{Solution}, objectives::Vector{Symbol};
    size=(300, 300)  # Per subplot
)
    n = length(objectives)
    fig = Figure(size=(size[1] * n, size[2] * n))

    for (i, obj_y) in enumerate(objectives)
        for (j, obj_x) in enumerate(objectives)
            ax = Axis(fig[i, j])

            if i == j
                # Diagonal: histogram
                vals = [s.objectives[obj_x] for s in solutions]
                hist!(ax, vals, color=:dodgerblue)
                ax.title = String(obj_x)
            else
                # Off-diagonal: scatter
                optimal = filter(s -> s.is_pareto_optimal, solutions)
                dominated = filter(s -> !s.is_pareto_optimal, solutions)

                scatter!(ax,
                    [s.objectives[obj_x] for s in dominated],
                    [s.objectives[obj_y] for s in dominated],
                    color=(:gray, 0.3),
                    markersize=4
                )

                scatter!(ax,
                    [s.objectives[obj_x] for s in optimal],
                    [s.objectives[obj_y] for s in optimal],
                    color=:dodgerblue,
                    markersize=6
                )
            end

            # Labels only on edges
            if j == 1
                ax.ylabel = String(obj_y)
            else
                hideydecorations!(ax)
            end

            if i == n
                ax.xlabel = String(obj_x)
            else
                hidexdecorations!(ax)
            end
        end
    end

    fig
end

# =============================================================================
# Radar/Spider Chart for Solution Comparison
# =============================================================================

"""
    plot_radar_comparison(solutions::Vector{Solution}, objectives::Vector{Symbol})

Radar chart comparing multiple solutions across objectives.
"""
function plot_radar_comparison(solutions::Vector{Solution}, objectives::Vector{Symbol};
    size=(800, 800),
    normalize=true
)
    n_obj = length(objectives)
    angles = range(0, 2π - 2π/n_obj, length=n_obj)

    fig = Figure(size=size)
    ax = PolarAxis(fig[1, 1],
        title="Solution Comparison",
        thetalimits=(0, 2π)
    )

    # Normalize values if requested
    if normalize
        mins = Dict(obj => minimum(s.objectives[obj] for s in solutions) for obj in objectives)
        maxs = Dict(obj => maximum(s.objectives[obj] for s in solutions) for obj in objectives)
    end

    colors = distinguishable_colors(length(solutions), [RGB(1,1,1), RGB(0,0,0)], dropseed=true)

    for (idx, sol) in enumerate(solutions)
        values = Float64[]
        for obj in objectives
            val = sol.objectives[obj]
            if normalize
                range_val = maxs[obj] - mins[obj]
                val = range_val > 0 ? (val - mins[obj]) / range_val : 0.5
            end
            push!(values, val)
        end

        # Close the polygon
        push!(values, values[1])
        all_angles = [angles..., angles[1]]

        lines!(ax, all_angles, values,
            color=colors[idx],
            linewidth=2,
            label=sol.id)

        scatter!(ax, all_angles[1:end-1], values[1:end-1],
            color=colors[idx],
            markersize=8)
    end

    # Add objective labels
    for (i, obj) in enumerate(objectives)
        text!(ax, angles[i], 1.1,
            text=String(obj),
            fontsize=12,
            align=(:center, :center))
    end

    axislegend(ax, position=:rt)

    fig
end

# =============================================================================
# Sample Data
# =============================================================================

"""Generate sample Pareto solutions"""
function sample_solutions(n=50)
    solutions = Solution[]

    for i in 1:n
        # Generate random solutions
        cost = rand() * 10000 + 5000
        time = rand() * 400 + 100
        carbon = rand() * 5000 + 1000
        labor = rand()

        push!(solutions, Solution(
            "route-$(lpad(i, 3, '0'))",
            Dict(
                :cost => cost,
                :time => time,
                :carbon => carbon,
                :labor_score => labor
            ),
            false,  # Will compute Pareto optimality
            Dict()
        ))
    end

    # Compute Pareto optimality (minimizing all objectives except labor_score)
    for sol in solutions
        is_dominated = false
        for other in solutions
            if sol.id != other.id
                # Check if other dominates sol
                dominates = (
                    other.objectives[:cost] <= sol.objectives[:cost] &&
                    other.objectives[:time] <= sol.objectives[:time] &&
                    other.objectives[:carbon] <= sol.objectives[:carbon] &&
                    other.objectives[:labor_score] >= sol.objectives[:labor_score] &&
                    (
                        other.objectives[:cost] < sol.objectives[:cost] ||
                        other.objectives[:time] < sol.objectives[:time] ||
                        other.objectives[:carbon] < sol.objectives[:carbon] ||
                        other.objectives[:labor_score] > sol.objectives[:labor_score]
                    )
                )
                if dominates
                    is_dominated = true
                    break
                end
            end
        end

        # Update Pareto status
        solutions[findfirst(s -> s.id == sol.id, solutions)] = Solution(
            sol.id, sol.objectives, !is_dominated, sol.metadata
        )
    end

    solutions
end

end # module

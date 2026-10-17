"""
    TraitMakie

A plotting library written as a trait module (`PlotCore`), with an ordinary layer that offers a
Makie-like interface: `lines(x, y)`, `scatter!(fig, x, y)`, `save(path, fig)`. The second
demonstrator of the trait world's viability; see README.md for the measurements.

This module is the ordinary one that pairs with the trait module. It converts arguments such as
`x, y` vectors into one value the trait module's bounds take (note "Types that only convert").
PlotCore calls Cairo directly (wrapping by facts).
"""
module TraitMakie
using TraitWorld

include("PlotCore.jl")
using .PlotCore
export lines, lines!, scatter, scatter!, barplot, barplot!, hist, hist!, vlines!, save, figure, recolor!, Positions, npoints, pointx, pointy, ColorSpec, rgba, Plot

# --- the ordinary interface --------------------------------------------------------------------------

figure(; size = (600, 400), title = "") = PlotCore.newfigure(Int(size[1]), Int(size[2]), String(title))

"`x, y` vectors as one value PlotCore's bounds take: an n × 2 matrix (an explicit conversion)."
_xy(x::AbstractVector, y::AbstractVector) = hcat(Vector{Float64}(x), Vector{Float64}(y))
_color(c::Symbol) = c
_color(c::NTuple{4,<:Real}) = NTuple{4,Float64}(c)
_color(c::NTuple{3,<:Real}) = (Float64(c[1]), Float64(c[2]), Float64(c[3]), 1.0)
_color(c) = c                                       # a user's type conforming to ColorSpec

lines!(fig::PlotCore.Figure, x::AbstractVector, y::AbstractVector; color = :blue, linewidth = 1.5) =
    (PlotCore.add_lines!(fig, _xy(x, y), _color(color), Float64(linewidth)); fig)
lines!(fig::PlotCore.Figure, data; color = :blue, linewidth = 1.5) =              # data conforming to Positions
    (PlotCore.add_lines!(fig, data, _color(color), Float64(linewidth)); fig)
scatter!(fig::PlotCore.Figure, x::AbstractVector, y::AbstractVector; color = :black, markersize = 6) =
    (PlotCore.add_scatter!(fig, _xy(x, y), _color(color), Float64(markersize)); fig)
scatter!(fig::PlotCore.Figure, data; color = :black, markersize = 6) =
    (PlotCore.add_scatter!(fig, data, _color(color), Float64(markersize)); fig)
barplot!(fig::PlotCore.Figure, x::AbstractVector, y::AbstractVector; color = :blue, width = nothing) =
    (PlotCore.add_bars!(fig, _xy(x, y), _color(color), Float64(something(width, _gap(x)))); fig)
"Bars' default width: 80% of the smallest gap between neighbouring x."
_gap(x) = length(x) < 2 ? 1.0 : 0.8 * minimum(diff(sort(Vector{Float64}(x))))

"A histogram of `x` with `bins` equal bins, as bars."
function hist!(fig::PlotCore.Figure, x::AbstractVector; bins::Integer = 10, color = :blue)
    v = Vector{Float64}(x)
    lo, hi = extrema(v)
    w = hi > lo ? (hi - lo) / bins : 1.0
    counts = zeros(bins)
    for xi in v
        counts[clamp(floor(Int, (xi - lo) / w) + 1, 1, bins)] += 1
    end
    return barplot!(fig, [lo + (k - 0.5) * w for k in 1:bins], counts; color, width = w)
end

"Vertical lines at `xs` across the plot area."
vlines!(fig::PlotCore.Figure, xs::AbstractVector; color = :black, linewidth = 1.5) =
    (PlotCore.add_vlines!(fig, _xy(xs, zeros(length(xs))), _color(color), Float64(linewidth)); fig)
vlines!(fig::PlotCore.Figure, x::Real; kw...) = vlines!(fig, [x]; kw...)

barplot(args...; title = "", size = (600, 400), kw...) = barplot!(figure(; size, title), args...; kw...)
hist(args...; title = "", size = (600, 400), kw...) = hist!(figure(; size, title), args...; kw...)
lines(args...; title = "", size = (600, 400), kw...) = lines!(figure(; size, title), args...; kw...)
scatter(args...; title = "", size = (600, 400), kw...) = scatter!(figure(; size, title), args...; kw...)

"Give the figure's plot `k` another colour: any value `ColorSpec` takes, whatever the colour was before."
recolor!(fig::PlotCore.Figure, k::Integer, color) = (PlotCore.recolor!(fig, Int(k), _color(color)); fig)

"Render the figure into a PNG file."
save(path::AbstractString, fig::PlotCore.Figure) = (PlotCore.render_png(fig, String(path)); path)

# a precompile workload: both recipes, a single colour and one per point, into a temporary file
TraitWorld.@workload begin
    xs = collect(range(0.0, 2pi; length = 50))
    f = lines(xs, sin.(xs); title = "workload")
    scatter!(f, xs, cos.(xs); color = [(0.2, 0.4, 0.8, 1.0) for _ in xs])
    scatter!(f, xs, sin.(xs); color = :red)                      # the library's own colour types, each recipe
    scatter!(f, xs, sin.(xs); color = (0.1, 0.2, 0.3))
    lines!(f, [(0.0, 0.0), (1.0, 1.0)]; color = (1.0, 0.0, 0.0))
    recolor!(f, 2, :red)
    path = tempname() * ".png"
    save(path, f)
    h = hist(xs; bins = 24, title = "workload", size = (1200, 800))
    vlines!(h, 1.0; color = :red)
    save(path, h)
    rm(path; force = true)
end

end

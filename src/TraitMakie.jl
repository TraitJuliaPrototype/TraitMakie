"""
    TraitMakie

A plotting library written as a trait module (`PlotCore`), with an ordinary layer that offers a
Makie-like interface: `lines(x, y)`, `scatter!(fig, x, y)`, `p = hist!(fig, x)`, `p.color = :red`,
`save(path, fig)`; and upstream Makie's user API for figures with axes: `fig = Figure(size = (800, 600))`,
`ax = Axis(fig[2, 1]; xscale = log10)`, `lines!(ax, x, y)`, `save(path, fig; px_per_unit = 1)`.
The second demonstrator of the trait world's viability; see README.md.

This module is the ordinary one that pairs with the trait module. It converts arguments such as
`x, y` vectors into one value the trait module's bounds take (note "Types that only convert"),
checks names (colours, markers, steps) with messages that list the choices, and translates a
value assigned to a plot's attribute at the attribute's bound (`p.color = x`). PlotCore calls
Cairo directly (wrapping by facts).
"""
module TraitMakie
using TraitWorld
# the old recipe API's machinery lives in MakieCompat, which defines methods on the names below (X3, slice 2;
# the lean-core memo §1.2), and its statistics recipes in MakieCompatStats, a group with StatsBase (slice 4): the
# umbrella that owns the names declares both joint owners (traits §10.1)
@joint_owners MakieCompat MakieCompatStats

include("PlotCore.jl")
using .PlotCore
export Figure, Axis, lines, lines!, scatter, scatter!, barplot, barplot!, hist, hist!, vlines!, stairs, stairs!, band, band!,
       poly, poly!, text!, linesegments!, plot!, save, figure, recolor!, hidedecorations!, limits!, Live, onchange,
       Positions, npoints, pointx, pointy, Sample, nvalues, value, ColorSpec, rgba, MarkerShape, outline, Scale, Plot,
       Colormap, MappedColors, Lines, Scatter, Bars, VLines, Poly, Labels, Stairs, Hist, Band

# --- names, checked where they are given ------------------------------------------------------------

# a name becomes a `ColorName` or `MarkerName`, which checks it: an unknown name is refused where it is given
_color(c::Symbol) = PlotCore.ColorName(c)
_color(c::NTuple{4,<:Real}) = NTuple{4,Float64}(c)
_color(c::NTuple{3,<:Real}) = (Float64(c[1]), Float64(c[2]), Float64(c[3]), 1.0)
_color(c::AbstractVector{Symbol}) = PlotCore.ColorName[PlotCore.ColorName(s) for s in c]
_color(c::AbstractVector{<:Tuple}) = NTuple{4,Float64}[_color(x) for x in c]
_color(c::AbstractVector{<:Real}) = _color(c, :viridis, nothing)
_color(c) = c                                       # a user's type conforming to ColorSpec
"""
A colour given with a colormap and a colour range (upstream's `color`, `colormap`, `colorrange`): numbers, one per point,
are mapped through the colormap, the range `nothing` taken from the numbers; any other colour is taken as it is.
"""
_color(c::AbstractVector{<:Real}, colormap, colorrange) =
    PlotCore.MappedColors(Vector{Float64}(c), _colormap(colormap), _crange(c, colorrange)...)
_color(c::Real, colormap, colorrange) = _color([c], colormap, colorrange)
_color(c, colormap, colorrange) = _color(c)
_colormap(m::Symbol) = PlotCore.ColormapName(m)
_colormap(m::AbstractVector) = NTuple{4,Float64}[_rgba(_color(x)) for x in m]
_colormap(m) = m                                    # a user's type conforming to Colormap
_rgba(c::PlotCore.ColorName) = PlotCore.NAMED[c.name]
_rgba(c::NTuple{4,Float64}) = c
"The colour range: as given, else the finite numbers' extrema (widened by ½ either side where they are one value)."
_crange(c, r::Tuple{Real,Real}) = (Float64(r[1]), Float64(r[2]))
function _crange(c, ::Nothing)
    lo, hi = Inf, -Inf
    for v in c
        isfinite(v) || continue
        lo = min(lo, Float64(v)); hi = max(hi, Float64(v))
    end
    isfinite(lo) || return (0.0, 1.0)
    return lo < hi ? (lo, hi) : (lo - 0.5, hi + 0.5)
end
_marker(m::Symbol) = PlotCore.MarkerName(m)
_marker(m::AbstractVector{Symbol}) = PlotCore.MarkerName[PlotCore.MarkerName(s) for s in m]
_marker(m) = m
_step(s::Symbol) = s in (:pre, :post, :center) ? s :
    throw(ArgumentError("unknown step :$s. The steps are :pre, :post and :center"))
_bins(b::Integer) = b >= 1 ? Int(b) : throw(ArgumentError("bins must be at least 1, not $b"))
_align(a::Symbol) = a in (:left, :center, :right) ? a :
    throw(ArgumentError("unknown alignment :$a. The alignments are :left, :center and :right"))

"`x, y` vectors as one value PlotCore's bounds take: an n × 2 matrix (an explicit conversion)."
_xy(x::AbstractVector, y::AbstractVector) =
    length(x) == length(y) ? hcat(Vector{Float64}(x), Vector{Float64}(y)) :
    throw(DimensionMismatch("x has $(length(x)) values, y has $(length(y))"))
_sample(x::Vector{<:Real}) = x
_sample(x::AbstractVector{<:Real}) = Vector{Float64}(x)
_sample(x) = x                                      # a user's type conforming to Sample

# --- attributes: a value assigned to a plot's field is translated at the field's bound -----------
#
# A recipe's attribute that may change shape is a field typed by a trait. Julia's `setproperty!`
# converts an assigned value to the field's type: `convert(X, x)` is `x` for a member, and the
# library translates any other (traits §8.1). So `p.color = :red`, `p.color = [(1, 0, 0, 1), …]`,
# `p.marker = :rect`, `p.pos = (x, y)` work at the prompt, for the library's recipes and a user's alike.
Base.convert(::Type{ColorSpec}, x) = _color(x)
Base.convert(::Type{MarkerShape}, x) = _marker(x)
# a member is itself: the joint methods with Base's `convert(::Type{T}, x::T) where T`
Base.convert(::Type{ColorSpec}, x::ColorSpec) = x
Base.convert(::Type{MarkerShape}, x::MarkerShape) = x
Base.convert(::Type{Positions}, xy::Tuple{AbstractVector,AbstractVector}) = _xy(xy[1], xy[2])
Base.convert(::Type{Sample}, x::AbstractVector{<:Real}) = _sample(x)

# --- the ordinary interface --------------------------------------------------------------------------

figure(; size = (600, 400), title = "", xlabel = "", ylabel = "") =
    PlotCore.newfigure(Int(size[1]), Int(size[2]), String(title), String(xlabel), String(ylabel))
const Fig = PlotCore.Figure
"The axis a figure's own calls (`lines!(fig, …)`) draw into: its first."
_axis(fig::Fig) = isempty(fig.axes) ? throw(ArgumentError("the figure has no axis; add one with `Axis(fig[1, 1])`")) : fig.axes[1]

# Each `f!(fig, …)` adds a plot and returns it; its attributes may be changed later (`p.color = x`).
lines!(fig::Fig, x::AbstractVector, y::AbstractVector; kw...) = lines!(fig, _xy(x, y); kw...)
lines!(fig::Fig, data; color = :blue, linewidth = 1.5) =                     # data conforming to Positions
    PlotCore.add_lines!(_axis(fig), data, _color(color), Float64(linewidth))
scatter!(fig::Fig, x::AbstractVector, y::AbstractVector; kw...) = scatter!(fig, _xy(x, y); kw...)
scatter!(fig::Fig, data; color = :black, markersize = 6, marker = :circle) =
    PlotCore.add_scatter!(_axis(fig), data, _color(color), Float64(markersize), _marker(marker))
barplot!(fig::Fig, x::AbstractVector, y::AbstractVector; color = :blue, width = nothing) =
    PlotCore.add_bars!(_axis(fig), _xy(x, y), _color(color), Float64(something(width, _gap(x))))
"Bars' default width: 80% of the smallest gap between neighbouring x."
_gap(x) = length(x) < 2 ? 1.0 : 0.8 * minimum(diff(sort(Vector{Float64}(x))))
"A histogram of `x` (a vector of numbers, or a value conforming to `Sample`) in `bins` equal bins: a recipe whose child is a `Bars`."
hist!(fig::Fig, x; bins::Integer = 10, color = :blue) = PlotCore.add_hist!(_axis(fig), _sample(x), _bins(bins), _color(color))
"Vertical lines at `xs` across the plot area."
vlines!(fig::Fig, xs::AbstractVector; color = :black, linewidth = 1.5) =
    PlotCore.add_vlines!(_axis(fig), _xy(xs, zeros(length(xs))), _color(color), Float64(linewidth))
vlines!(fig::Fig, x::Real; kw...) = vlines!(fig, [x]; kw...)
"A step line through points; `step` is `:pre` (default), `:post` or `:center`. A recipe whose child is a `Lines`."
stairs!(fig::Fig, x::AbstractVector, y::AbstractVector; kw...) = stairs!(fig, _xy(x, y); kw...)
stairs!(fig::Fig, data; step = :pre, color = :blue, linewidth = 1.5) =
    PlotCore.add_stairs!(_axis(fig), data, _step(step), _color(color), Float64(linewidth))
"A band between `lower` and `upper` at `x`. A recipe whose child is a `Poly`."
band!(fig::Fig, x::AbstractVector, lower::AbstractVector, upper::AbstractVector; kw...) = band!(fig, _xy(x, lower), _xy(x, upper); kw...)
band!(fig::Fig, lower, upper; color = (0.12, 0.35, 0.8, 0.3)) = PlotCore.add_band!(_axis(fig), lower, upper, _color(color))
"A filled polygon through points."
poly!(fig::Fig, x::AbstractVector, y::AbstractVector; kw...) = poly!(fig, _xy(x, y); kw...)
poly!(fig::Fig, data; color = :gray) = PlotCore.add_poly!(_axis(fig), data, _color(color))
"Text `texts[i]` at point `i`."
text!(fig::Fig, x::AbstractVector, y::AbstractVector, texts::AbstractVector; kw...) = text!(fig, _xy(x, y), texts; kw...)
text!(fig::Fig, x::Real, y::Real, s::AbstractString; kw...) = text!(fig, [x], [y], [s]; kw...)
text!(fig::Fig, data, texts::AbstractVector; color = :black, fontsize = 11, align = :left) =
    PlotCore.add_labels!(_axis(fig), data, String[string(s) for s in texts], _color(color), Float64(fontsize), _align(align))
"Add a plot of a user's recipe (a value of a type conforming to `Plot`) and return it."
plot!(fig::Fig, p) = (PlotCore.add_plot!(_axis(fig), p); p)

# `f(args…)` makes a figure with one plot and returns the figure
for f in (:lines, :scatter, :barplot, :hist, :stairs, :band, :poly)
    f! = Symbol(f, "!")
    @eval $f(args...; title = "", size = (600, 400), xlabel = "", ylabel = "", kw...) =
        (fig = figure(; size, title, xlabel, ylabel); $f!(fig, args...; kw...); fig)
end

"Give the figure's plot `k` another colour: any value `ColorSpec` takes, whatever the colour was before."
recolor!(fig::Fig, k::Integer, color) = (PlotCore.recolor!(_axis(fig), Int(k), _color(color)); fig)

"Render the figure into a PNG file, `px_per_unit` pixels per unit of the figure's size."
save(path::AbstractString, fig::Fig; px_per_unit::Real = 1) = (PlotCore.render_png(fig, String(path), Float64(px_per_unit)); path)

# --- upstream Makie's user API for figures with axes ------------------------------------------------
#
# The calls of a Makie session, unchanged: `Figure(size = …)`, `fig[r, c]`, `Axis(fig[r, c]; xscale = log10)`,
# `lines!(ax, x, y)`, `save(path, fig; px_per_unit = 1)`. Each maps to the core's figure, axes and primitives.

"Upstream's `Figure(; size)`: a figure with no axis yet; `Axis(fig[r, c])` adds one."
PlotCore.Figure(; size = (600, 450)) = PlotCore.Figure(Int(size[1]), Int(size[2]), PlotCore.Axis[])
"A cell of a figure's grid, `fig[r, c]`: where an `Axis` goes."
struct GridPosition
    fig::Fig
    row::Int
    col::Int
end
Base.getindex(fig::Fig, r::Integer, c::Integer) = GridPosition(fig, Int(r), Int(c))
"""
Upstream's `Axis(fig[r, c]; xscale, yscale, title, xlabel, ylabel)`: an axis in that cell. A scale is any value
conforming to `Scale` (`identity`, `log10`, a user's).
"""
PlotCore.Axis(gp::GridPosition; xscale = identity, yscale = identity, title = "", xlabel = "", ylabel = "") =
    PlotCore.add_axis!(gp.fig, gp.row, gp.col, xscale, yscale, String(title), String(xlabel), String(ylabel))
const Ax = PlotCore.Axis
"A plot's colour: as given, else the axis's next of the palette (upstream's cycle)."
_cycled(ax::Ax, color) = color === nothing ? PlotCore.nextcolor!(ax) : _color(color)
_cycled(ax::Ax, color, colormap, colorrange) = color === nothing ? PlotCore.nextcolor!(ax) : _color(color, colormap, colorrange)
lines!(ax::Ax, x::AbstractVector, y::AbstractVector; kw...) = lines!(ax, _xy(x, y); kw...)
lines!(ax::Ax, data; color = nothing, linewidth = 1.5, colormap = :viridis, colorrange = nothing) =
    PlotCore.add_lines!(ax, data, _cycled(ax, color, colormap, colorrange), Float64(linewidth))
scatter!(ax::Ax, x::AbstractVector, y::AbstractVector; kw...) = scatter!(ax, _xy(x, y); kw...)
scatter!(ax::Ax, data; color = nothing, markersize = 9, marker = :circle, colormap = :viridis, colorrange = nothing) =
    PlotCore.add_scatter!(ax, data, _cycled(ax, color, colormap, colorrange), Float64(markersize), _marker(marker))
"Line segments between points 1 and 2, 3 and 4, …: one line each."
function linesegments!(ax::Ax, data; color = nothing, linewidth = 1.5, linestyle = nothing)
    c = _cycled(ax, color)
    n = npoints(data)
    for k in 1:2:n-1
        PlotCore.add_lines!(ax, [pointx(data, k) pointy(data, k); pointx(data, k + 1) pointy(data, k + 1)], c, Float64(linewidth))
    end
    return ax
end
"Upstream's `hidedecorations!(ax)`: no ticks, tick labels, grid or axis labels; the frame and the title stay."
hidedecorations!(ax::Ax) = (PlotCore.hidedecorations!(ax); ax)
"Upstream's `limits!(ax, xmin, xmax, ymin, ymax)`; `nothing` leaves a side to the data."
limits!(ax::Ax, x1, x2, y1, y2) = (PlotCore.setlimits!(ax, _lim(x1), _lim(x2), _lim(y1), _lim(y2)); ax)
limits!(ax::Ax, xs::Tuple, ys::Tuple) = limits!(ax, xs..., ys...)
_lim(::Nothing) = NaN
_lim(x::Real) = Float64(x)
"Add a plot of a user's recipe to the axis and return it."
plot!(ax::Ax, p) = (PlotCore.add_plot!(ax, p); p)
"Upstream's `text` and `linesegments`, by name: an old recipe's `Plot{typeof(text)}`; the user API has `text!` and `linesegments!`."
function text end
function linesegments end

# --- live data -------------------------------------------------------------------------------------

"""
    Live(x)

A value that changes: `live[] = y` replaces it, `onchange(f, live)` calls `f(y)` after each
replacement. A plot made from a `Live` reads its current value at each render (a `Live` of an
n × 2 matrix or of a vector of points conforms to `Positions`, of a vector of numbers to
`Sample`, by forwarding to its value), so `save` after `live[] = y` draws the new data, and
`onchange(_ -> save(path, fig), live)` redraws on every change. Ordinary code: no trait-world
code is involved in the notification.
"""
mutable struct Live{T}
    val::T
    const listeners::Vector{Any}
end
Live(x::T) where {T} = Live{T}(x, Any[])
Base.getindex(l::Live) = l.val
function Base.setindex!(l::Live, x)
    l.val = x
    for f in l.listeners
        f(l.val)
    end
    return l
end
"Call `f(value)` after each replacement of the live value; returns `f`."
onchange(f, l::Live) = (push!(l.listeners, f); f)
Base.show(io::IO, l::Live) = (print(io, "Live("); show(io, l.val); print(io, ")"))
# forwarding is declared per parameter value (forwarding for a whole family: not yet in TraitWorld)
@implement Positions Live{Matrix{Float64}} by val
@implement Positions Live{Vector{NTuple{2,Float64}}} by val
@implement Sample Live{Vector{Float64}} by val
@implement Sample Live{Vector{Int}} by val

# a precompile workload, run while the package image is built: every recipe, the library's own colour
# and marker types on each, an attribute changed after the plot was made, and live data, into a
# temporary file
if ccall(:jl_generating_output, Cint, ()) == 1
    let
    xs = collect(range(0.0, 2pi; length = 50))
    path = tempname() * ".png"
    f = lines(xs, sin.(xs); title = "workload")
    scatter!(f, xs, cos.(xs); color = [(0.2, 0.4, 0.8, 1.0) for _ in xs])
    scatter!(f, xs, sin.(xs); color = :red, marker = :rect)                    # the library's own colour types, each recipe
    s = scatter!(f, xs, sin.(xs); color = (0.1, 0.2, 0.3), marker = [k % 2 == 0 ? :diamond : :cross for k in eachindex(xs)])
    lines!(f, [(0.0, 0.0), (1.0, 1.0)]; color = (1.0, 0.0, 0.0))
    recolor!(f, 2, :red)
    s.color = [isodd(k) ? :green : :orange for k in eachindex(xs)]            # attributes changed after the plot was made
    s.marker = :utriangle
    s.pos = (xs, cos.(xs))
    save(path, f)
    h = hist(xs; bins = 24, title = "workload", size = (1200, 800))
    vlines!(h, 1.0; color = :red)
    save(path, h)
    g = figure(; title = "workload", xlabel = "x", ylabel = "y")
    st = stairs!(g, xs, sin.(xs); step = :post)
    st.step = :center
    st.color = :purple
    band!(g, xs, sin.(xs) .- 0.2, sin.(xs) .+ 0.2)
    poly!(g, [0.0, 1.0, 0.5], [0.0, 0.0, 1.0]; color = :green)
    text!(g, 1.0, 0.5, "label"; align = :center)
    hg = hist!(g, Int[1, 2, 2, 3]; bins = 3)
    hg.bins = 2
    hg.values = [0.5, 1.5]
    save(path, g)
    lv = Live([0.0 0.0; 1.0 1.0])                                                # live data
    lf = lines(lv)
    lp = Live([(0.0, 1.0), (1.0, 0.0)])
    scatter!(lf, lp)
    lh = Live([1.0, 2.0, 2.5])
    hist!(lf, lh; bins = 2)
    onchange(_ -> save(path, lf), lv)
    lv[] = [0.0 1.0; 1.0 0.0; 2.0 1.0]
    lh[] = [0.0, 3.0]
    save(path, lf)
    fu = Figure(size = (400, 300))                                               # upstream's user API: two axes, a log axis
    a1 = Axis(fu[1, 1]); a2 = Axis(fu[2, 1]; xscale = log10)
    for k in 1:3
        lines!(a1, xs, sin.(k .* xs))
        lines!(a2, exp10.(xs), cos.(k .* xs))
    end
    save(path, fu; px_per_unit = 1)
    rm(path; force = true)
    end
end


"""
    TraitMakie.OldAPI

The old Makie recipe API's names and types, owned by the umbrella (the lean-core memo §1.2): `Plot{F, T}`,
the empty generic functions an old recipe extends or calls. Their machinery is MakieCompat's, a joint owner.
"""
module OldAPI
# the plotting functions are the user API's (one function per name, as upstream's): an old recipe's `lines!(plot, …)` and a
# user's `lines!(ax, …)` are methods of the same function
import ..TraitMakie: lines!, lines, scatter!, scatter, text!, text, linesegments!, linesegments
"""
Upstream's `Plot{F, T}`: the plotting function's type `F`, the converted arguments' types `T`, the arguments as given;
its parent (the plot whose recipe made it, or the place a top-level plot was added to, as the layer represents it).
"""
mutable struct Plot{F, T}
    converted::T
    args::Vector{Any}
    attributes::Dict{Symbol, Any}
    graph::Dict{Symbol, Any}
    children::Vector{Any}
    parent::Any
end
"""
Upstream's `Attributes`: names to values. A value may be a node of a plot or an `Observable`. Read as
`a[:color]` or `a.color`; splatted as keywords (`stephist!(fig, x; a...)`).
"""
struct Attributes
    attributes::Dict{Symbol, Any}
end
Attributes(; kw...) = Attributes(Dict{Symbol, Any}(kw))
Attributes(ps::Pair{Symbol}...) = Attributes(Dict{Symbol, Any}(ps...))
Base.getindex(a::Attributes, k::Symbol) = getfield(a, :attributes)[k]
Base.setindex!(a::Attributes, v, k::Symbol) = (getfield(a, :attributes)[k] = v; a)
Base.getproperty(a::Attributes, k::Symbol) = k === :attributes ? getfield(a, :attributes) : a[k]
Base.haskey(a::Attributes, k::Symbol) = haskey(getfield(a, :attributes), k)
Base.keys(a::Attributes) = keys(getfield(a, :attributes))
Base.length(a::Attributes) = length(getfield(a, :attributes))
Base.iterate(a::Attributes, s...) = iterate(getfield(a, :attributes), s...)
"The recipe author's `plot!`, one method per recipe."
function plot! end
"A recipe's attribute defaults, as name => value pairs."
function documented_attributes end
"A recipe's conversion trait (`PointBased()` for `stairs`)."
function conversion_trait end
"A recipe's attributes that another plot type also has."
function shared_attributes end
"A recipe's conversion of its arguments, by plot type (upstream's cascade, the cases a recipe defines)."
function convert_arguments end
"A mesh child of an old-style plot."
function mesh! end
function mesh end
"Primitives an old recipe's file names (`hist.jl`'s plot types), without machinery here."
function heatmap end
function voxels end
end

end

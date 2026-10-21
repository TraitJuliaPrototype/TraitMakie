"""
    TraitMakie

A plotting library written as a trait module (`PlotCore`), with an ordinary layer that offers a
Makie-like interface: `lines(x, y)`, `scatter!(fig, x, y)`, `p = hist!(fig, x)`, `p.color = :red`,
`save(path, fig)`. The second demonstrator of the trait world's viability; see README.md.

This module is the ordinary one that pairs with the trait module. It converts arguments such as
`x, y` vectors into one value the trait module's bounds take (note "Types that only convert"),
checks names (colours, markers, steps) with messages that list the choices, and translates a
value assigned to a plot's attribute at the attribute's bound (`p.color = x`). PlotCore calls
Cairo directly (wrapping by facts).
"""
module TraitMakie
using TraitWorld

include("PlotCore.jl")
using .PlotCore
export lines, lines!, scatter, scatter!, barplot, barplot!, hist, hist!, vlines!, stairs, stairs!, band, band!,
       poly, poly!, text!, plot!, save, figure, recolor!, Live, onchange,
       Positions, npoints, pointx, pointy, Sample, nvalues, value, ColorSpec, rgba, MarkerShape, outline, Plot,
       Lines, Scatter, Bars, VLines, Poly, Labels, Stairs, Hist, Band

# --- names, checked where they are given ------------------------------------------------------------

_names(d) = join((":" * string(k) for k in sort!(collect(keys(d)))), ", ")
function _named(c::Symbol)
    haskey(PlotCore.NAMED, c) && return c
    throw(ArgumentError("unknown colour :$c. The named colours are $(_names(PlotCore.NAMED)); a colour may also be an RGB or RGBA tuple, a vector of colours (one per point), or a value of a type conforming to ColorSpec"))
end
_color(c::Symbol) = _named(c)
_color(c::NTuple{4,<:Real}) = NTuple{4,Float64}(c)
_color(c::NTuple{3,<:Real}) = (Float64(c[1]), Float64(c[2]), Float64(c[3]), 1.0)
_color(c::AbstractVector{Symbol}) = Symbol[_named(s) for s in c]
_color(c::AbstractVector{<:Tuple}) = NTuple{4,Float64}[_color(x) for x in c]
_color(c) = c                                       # a user's type conforming to ColorSpec
function _mark(m::Symbol)
    haskey(PlotCore.MARKERS, m) && return m
    throw(ArgumentError("unknown marker :$m. The markers are $(_names(PlotCore.MARKERS)), a vector of them (one per point), or a value of a type conforming to MarkerShape"))
end
_marker(m::Symbol) = _mark(m)
_marker(m::AbstractVector{Symbol}) = Symbol[_mark(s) for s in m]
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
# A recipe's attribute that may change shape is a field of a trait's name, `Kept{X}`. Julia's
# `setproperty!` converts an assigned value to the field's type; these methods make that conversion
# the boundary's translation at `X` (after the ordinary layer's checks), so `p.color = :red`,
# `p.color = [(1, 0, 0, 1), …]`, `p.marker = :rect`, `p.pos = (x, y)` work at the prompt, for the
# library's recipes and a user's alike. A plain value gets the trait's default there, as TraitWorld's
# own conversion gives it; a held value or a cast keeps its attribute. (TraitWorld converts a plain
# value for every trait; these methods add the shape translation.)
_shape(::Type{ColorSpec}, x) = _color(x)
_shape(::Type{MarkerShape}, x) = _marker(x)
_shape(::Type{Positions}, xy::Tuple{AbstractVector,AbstractVector}) = _xy(xy[1], xy[2])
_shape(::Type{Positions}, x) = x
_shape(::Type{Sample}, x) = _sample(x)
for X in (ColorSpec, MarkerShape, Positions, Sample)
    @eval Base.convert(::Type{Kept{$X}}, x) = Kept{$X}(_shape($X, x))     # a plain value: the trait's default
    @eval Base.convert(::Type{Kept{$X}}, x::Kept{$X}) = x
    @eval Base.convert(::Type{Kept{$X}}, x::Union{TObj,Dynamic{$X},Compiled{$X}}) = Kept{$X}(x)
    @eval Base.convert(::Type{Kept{$X}}, x::Union{TraitWorld.CompiledFor,TraitWorld.WithDynamic}) = Kept{$X}(x)
end

# --- the ordinary interface --------------------------------------------------------------------------

figure(; size = (600, 400), title = "", xlabel = "", ylabel = "") =
    PlotCore.newfigure(Int(size[1]), Int(size[2]), String(title), String(xlabel), String(ylabel))
const Fig = PlotCore.Figure

# Each `f!(fig, …)` adds a plot and returns it; its attributes may be changed later (`p.color = x`).
lines!(fig::Fig, x::AbstractVector, y::AbstractVector; kw...) = lines!(fig, _xy(x, y); kw...)
lines!(fig::Fig, data; color = :blue, linewidth = 1.5) =                     # data conforming to Positions
    PlotCore.add_lines!(fig, data, _color(color), Float64(linewidth))
scatter!(fig::Fig, x::AbstractVector, y::AbstractVector; kw...) = scatter!(fig, _xy(x, y); kw...)
scatter!(fig::Fig, data; color = :black, markersize = 6, marker = :circle) =
    PlotCore.add_scatter!(fig, data, _color(color), Float64(markersize), _marker(marker))
barplot!(fig::Fig, x::AbstractVector, y::AbstractVector; color = :blue, width = nothing) =
    PlotCore.add_bars!(fig, _xy(x, y), _color(color), Float64(something(width, _gap(x))))
"Bars' default width: 80% of the smallest gap between neighbouring x."
_gap(x) = length(x) < 2 ? 1.0 : 0.8 * minimum(diff(sort(Vector{Float64}(x))))
"A histogram of `x` (a vector of numbers, or a value conforming to `Sample`) in `bins` equal bins: a recipe whose child is a `Bars`."
hist!(fig::Fig, x; bins::Integer = 10, color = :blue) = PlotCore.add_hist!(fig, _sample(x), _bins(bins), _color(color))
"Vertical lines at `xs` across the plot area."
vlines!(fig::Fig, xs::AbstractVector; color = :black, linewidth = 1.5) =
    PlotCore.add_vlines!(fig, _xy(xs, zeros(length(xs))), _color(color), Float64(linewidth))
vlines!(fig::Fig, x::Real; kw...) = vlines!(fig, [x]; kw...)
"A step line through points; `step` is `:pre` (default), `:post` or `:center`. A recipe whose child is a `Lines`."
stairs!(fig::Fig, x::AbstractVector, y::AbstractVector; kw...) = stairs!(fig, _xy(x, y); kw...)
stairs!(fig::Fig, data; step = :pre, color = :blue, linewidth = 1.5) =
    PlotCore.add_stairs!(fig, data, _step(step), _color(color), Float64(linewidth))
"A band between `lower` and `upper` at `x`. A recipe whose child is a `Poly`."
band!(fig::Fig, x::AbstractVector, lower::AbstractVector, upper::AbstractVector; kw...) = band!(fig, _xy(x, lower), _xy(x, upper); kw...)
band!(fig::Fig, lower, upper; color = (0.12, 0.35, 0.8, 0.3)) = PlotCore.add_band!(fig, lower, upper, _color(color))
"A filled polygon through points."
poly!(fig::Fig, x::AbstractVector, y::AbstractVector; kw...) = poly!(fig, _xy(x, y); kw...)
poly!(fig::Fig, data; color = :gray) = PlotCore.add_poly!(fig, data, _color(color))
"Text `texts[i]` at point `i`."
text!(fig::Fig, x::AbstractVector, y::AbstractVector, texts::AbstractVector; kw...) = text!(fig, _xy(x, y), texts; kw...)
text!(fig::Fig, x::Real, y::Real, s::AbstractString; kw...) = text!(fig, [x], [y], [s]; kw...)
text!(fig::Fig, data, texts::AbstractVector; color = :black, fontsize = 11, align = :left) =
    PlotCore.add_labels!(fig, data, String[string(s) for s in texts], _color(color), Float64(fontsize), _align(align))
"Add a plot of a user's recipe (a value of a type conforming to `Plot`) and return it."
plot!(fig::Fig, p) = (PlotCore.add_plot!(fig, p); p)

# `f(args…)` makes a figure with one plot and returns the figure
for f in (:lines, :scatter, :barplot, :hist, :stairs, :band, :poly)
    f! = Symbol(f, "!")
    @eval $f(args...; title = "", size = (600, 400), xlabel = "", ylabel = "", kw...) =
        (fig = figure(; size, title, xlabel, ylabel); $f!(fig, args...; kw...); fig)
end

"Give the figure's plot `k` another colour: any value `ColorSpec` takes, whatever the colour was before."
recolor!(fig::Fig, k::Integer, color) = (PlotCore.recolor!(fig, Int(k), _color(color)); fig)

"Render the figure into a PNG file."
save(path::AbstractString, fig::Fig) = (PlotCore.render_png(fig, String(path)); path)

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

# a precompile workload: every recipe, the library's own colour and marker types on each, an
# attribute changed after the plot was made, and live data, into a temporary file
TraitWorld.@workload begin
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
    rm(path; force = true)
end

end

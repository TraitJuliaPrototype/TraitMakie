# PlotCore: the trait module. Data, colours and plots are traits; plots are kept in an axis as
# dynamic values; the drawing loops run in workers compiled per key (what the bounds see):
#   - `Positions`: what a plot reads from data. A user type that holds such data in a field
#     forwards to it and runs the library's compiled code;
#   - `ColorSpec`: a colour, or one per point;
#   - `Plot`: a recipe. `Lines` and `Scatter` are the library's own; a user's recipe conforms too.
# The Cairo backend stays outside the trait world: the drawing primitives are declared calls into
# the ordinary module around this one (rule 1: calls upward).
@trait_module module PlotCore
using TraitWorld
export Positions, npoints, pointx, pointy, ColorSpec, rgba, Plot, draw!, datalimits,
       Figure, Axis, Lines, Scatter, Canvas, Transform2D, add_lines!, add_scatter!, render_png, newfigure, recolor!, setcolor!

# --- the traits --------------------------------------------------------------------------------

"Points a plot reads: x and y by index."
@trait Positions begin
    npoints(p::Positions)::Int
    pointx(p::Positions, i::Int)::Float64
    pointy(p::Positions, i::Int)::Float64
end
@implement Positions Matrix{Float64} begin            # n × 2: what the ordinary layer converts `x, y` to
    npoints(p) = size(p, 1)
    pointx(p, i) = p[i, 1]
    pointy(p, i) = p[i, 2]
end
@implement Positions Vector{NTuple{2,Float64}} begin
    npoints(p) = length(p)
    pointx(p, i) = p[i][1]
    pointy(p, i) = p[i][2]
end

"A colour for each point (`i`); a single colour ignores `i`."
@trait ColorSpec begin
    rgba(c::ColorSpec, i::Int)::NTuple{4,Float64}
end
const NAMED = Dict{Symbol,NTuple{4,Float64}}(
    :black => (0.0, 0.0, 0.0, 1.0), :white => (1.0, 1.0, 1.0, 1.0), :red => (0.85, 0.15, 0.15, 1.0),
    :green => (0.15, 0.6, 0.2, 1.0), :blue => (0.12, 0.35, 0.8, 1.0), :orange => (0.95, 0.55, 0.1, 1.0),
    :gray => (0.5, 0.5, 0.5, 1.0), :purple => (0.5, 0.2, 0.65, 1.0))
@implement ColorSpec Symbol begin
    rgba(c, i) = get(NAMED, c, (0.0, 0.0, 0.0, 1.0))
end
@implement ColorSpec NTuple{4,Float64} begin
    rgba(c, i) = c
end
@implement ColorSpec Vector{NTuple{4,Float64}} begin
    rgba(c, i) = c[i]
end

# --- the canvas: a handle on the backend's surface, and the transform from data to pixels -----------

@handle Surface

"Where a plot draws: the backend's surface, kept as a handle (opaque here)."
struct Canvas
    surface::Surface
    width::Int
    height::Int
end

"Data to pixels: an affine map per axis (pixel y grows downwards)."
struct Transform2D
    ax::Float64
    bx::Float64
    ay::Float64
    by::Float64
end
@inline px(t::Transform2D, x::Float64) = t.ax * x + t.bx
@inline py(t::Transform2D, y::Float64) = t.ay * y + t.by

# the backend's primitives: declared calls into the ordinary module around this one
newsurface(w::Int, h::Int) = @call _cairo_surface(w, h)::Surface
polyline!(c::Canvas, xs::Vector{Float64}, ys::Vector{Float64}, col::NTuple{4,Float64}, lw::Float64) =
    @call _cairo_polyline!(c.surface, xs, ys, col, lw)::Nothing
circles!(c::Canvas, xs::Vector{Float64}, ys::Vector{Float64}, cols::Vector{NTuple{4,Float64}}, r::Float64) =
    @call _cairo_circles!(c.surface, xs, ys, cols, r)::Nothing
text!(c::Canvas, x::Float64, y::Float64, s::String, size::Float64, halign::Symbol) =
    @call _cairo_text!(c.surface, x, y, s, size, halign)::Nothing
fillrect!(c::Canvas, x::Float64, y::Float64, w::Float64, h::Float64, col::NTuple{4,Float64}) =
    @call _cairo_fillrect!(c.surface, x, y, w, h, col)::Nothing
writepng(c::Canvas, path::String) = @call _cairo_write_png(c.surface, path)::Nothing

# --- plots: a recipe trait, and the library's two recipes -----------------------------------------

"A recipe: its data limits, how it draws itself onto a canvas, and its colour, which may change shape."
@trait Plot begin
    datalimits(p::Plot)::NTuple{4,Float64}
    draw!(p::Plot, c::Canvas, t::Transform2D)::Nothing
    setcolor!(p::Plot, c::Dynamic{ColorSpec})::Nothing
end

"Lines through points. Its data and colour are kept as dynamic values: any conforming type."
mutable struct Lines
    pos::Positions                  # a trait's name in a field: Dynamic{Positions}
    color::ColorSpec                # Dynamic{ColorSpec}
    linewidth::Float64
end
"Markers at points."
mutable struct Scatter
    pos::Positions
    color::ColorSpec
    markersize::Float64
end

# the loops over data: bounded functions, so each runs compiled for the keys it is opened at
function limits(pos::Positions)
    n = npoints(pos)
    xmin, xmax, ymin, ymax = Inf, -Inf, Inf, -Inf
    for i in 1:n
        x, y = pointx(pos, i), pointy(pos, i)
        xmin = min(xmin, x); xmax = max(xmax, x); ymin = min(ymin, y); ymax = max(ymax, y)
    end
    return (xmin, xmax, ymin, ymax)
end
function pixels(pos::Positions, t::Transform2D)
    n = npoints(pos)
    xs = Vector{Float64}(undef, n)
    ys = Vector{Float64}(undef, n)
    for i in 1:n
        xs[i] = px(t, pointx(pos, i))
        ys[i] = py(t, pointy(pos, i))
    end
    return xs, ys
end
colors(c::ColorSpec, n::Int) = NTuple{4,Float64}[rgba(c, i) for i in 1:n]

# opening a dynamic value at a bound selects the worker by dispatch: the result is asserted here
datalimits(p::Lines) = limits(p.pos)::NTuple{4,Float64}
datalimits(p::Scatter) = limits(p.pos)::NTuple{4,Float64}
function draw!(p::Lines, c::Canvas, t::Transform2D)
    xs, ys = pixels(p.pos, t)::Tuple{Vector{Float64},Vector{Float64}}
    polyline!(c, xs, ys, rgba(p.color, 1), p.linewidth)
    return nothing
end
function draw!(p::Scatter, c::Canvas, t::Transform2D)
    xs, ys = pixels(p.pos, t)::Tuple{Vector{Float64},Vector{Float64}}
    circles!(c, xs, ys, colors(p.color, length(xs))::Vector{NTuple{4,Float64}}, p.markersize / 2)
    return nothing
end
setcolor!(p::Lines, c::Dynamic{ColorSpec}) = (p.color = c; nothing)
setcolor!(p::Scatter, c::Dynamic{ColorSpec}) = (p.color = c; nothing)
@implement Plot Lines
@implement Plot Scatter

# --- figure, axis, rendering --------------------------------------------------------------------

"An axis: its plots, kept as dynamic values (a trait's name in a container: Vector{Dynamic{Plot}})."
mutable struct Axis
    plots::Vector{Plot}
    title::String
    xlabel::String
    ylabel::String
end
struct Figure
    width::Int
    height::Int
    axis::Axis
end
"Give plot `k` another colour, of any conforming type: a symbol, a vector, a user's gradient (one dispatch per change)."
recolor!(f::Figure, k::Int, c::ColorSpec) = setcolor!(f.axis.plots[k], Dynamic{ColorSpec}(c))

newfigure(width::Int, height::Int, title::String) = Figure(width, height, Axis(Dynamic{Plot}[], title, "", ""))

add_lines!(f::Figure, pos::Positions, color::ColorSpec, linewidth::Float64) =
    (push!(f.axis.plots, Dynamic{Plot}(Lines(Dynamic{Positions}(pos), Dynamic{ColorSpec}(color), linewidth))); nothing)
add_scatter!(f::Figure, pos::Positions, color::ColorSpec, markersize::Float64) =
    (push!(f.axis.plots, Dynamic{Plot}(Scatter(Dynamic{Positions}(pos), Dynamic{ColorSpec}(color), markersize))); nothing)

"Linear ticks: about `n` round values covering [lo, hi]."
function ticks(lo::Float64, hi::Float64, n::Int)
    span = hi - lo
    span <= 0 && return [lo]
    raw = span / n
    mag = 10.0^floor(log10(raw))
    step = raw / mag < 1.5 ? mag : raw / mag < 3.5 ? 2mag : raw / mag < 7.5 ? 5mag : 10mag
    first = ceil(lo / step) * step
    return collect(first:step:hi + 1e-9 * span)
end
ticklabel(v::Float64) = abs(v - round(v)) < 1e-9 ? string(Int(round(v))) : string(round(v; sigdigits = 4))

"Render a figure into a PNG file."
function render_png(f::Figure, path::String)
    W, H = f.width, f.height
    c = Canvas(newsurface(W, H), W, H)
    fillrect!(c, 0.0, 0.0, Float64(W), Float64(H), (1.0, 1.0, 1.0, 1.0))
    ax = f.axis
    xmin, xmax, ymin, ymax = Inf, -Inf, Inf, -Inf
    for p in ax.plots
        l = datalimits(p)                              # one dispatch per plot
        xmin = min(xmin, l[1]); xmax = max(xmax, l[2]); ymin = min(ymin, l[3]); ymax = max(ymax, l[4])
    end
    if !isfinite(xmin)
        xmin, xmax, ymin, ymax = 0.0, 1.0, 0.0, 1.0
    end
    dx, dy = 0.05 * max(xmax - xmin, 1e-12), 0.05 * max(ymax - ymin, 1e-12)
    xmin -= dx; xmax += dx; ymin -= dy; ymax += dy
    l, r, top, b = 60.0, W - 20.0, 40.0, H - 40.0     # the plot area
    t = Transform2D((r - l) / (xmax - xmin), l - (r - l) / (xmax - xmin) * xmin,
                    -(b - top) / (ymax - ymin), b + (b - top) / (ymax - ymin) * ymin)
    black, gray = (0.0, 0.0, 0.0, 1.0), (0.85, 0.85, 0.85, 1.0)
    for v in ticks(xmin, xmax, 6)
        polyline!(c, [px(t, v), px(t, v)], [top, b], gray, 0.5)
        text!(c, px(t, v), b + 16.0, ticklabel(v), 11.0, :center)
    end
    for v in ticks(ymin, ymax, 5)
        polyline!(c, [l, r], [py(t, v), py(t, v)], gray, 0.5)
        text!(c, l - 6.0, py(t, v) + 4.0, ticklabel(v), 11.0, :right)
    end
    polyline!(c, [l, r, r, l, l], [top, top, b, b, top], black, 1.0)
    isempty(ax.title) || text!(c, (l + r) / 2, 24.0, ax.title, 14.0, :center)
    for p in ax.plots
        draw!(p, c, t)                                 # one dispatch per plot; its loops run compiled per key
    end
    writepng(c, path)
    return nothing
end

end

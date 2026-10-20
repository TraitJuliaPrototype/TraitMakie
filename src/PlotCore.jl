# PlotCore: the trait module. Data, colours, markers and plots are traits; plots are kept in an
# axis as dynamic values; the drawing loops run in workers compiled per key (what the bounds see):
#   - `Positions`: what a plot reads from data. A user type that holds such data in a field
#     forwards to it and runs the library's compiled code;
#   - `Sample`: what a histogram reads from data: values by index;
#   - `ColorSpec`: a colour, or one per point;
#   - `MarkerShape`: a marker's outline, one shape or one per point;
#   - `Plot`: a recipe. Primitives (`Lines`, `Scatter`, `Bars`, `VLines`, `Poly`, `Labels`) draw;
#     recipes with children (`Stairs`, `Hist`, `Band`) rebuild their children from their own
#     data and attributes at each render, so a changed attribute or a live source shows on the
#     next render. A user's recipe conforms too.
# Cairo is called directly (wrapping by facts, writeup/explorations/wrapping-by-facts.md): the
# trait world may call any Julia code; its compiled code depends on Cairo's methods only through
# dispatch facts at concrete signatures.
@trait_module module PlotCore
using TraitWorld
using Cairo: Cairo
export Positions, npoints, pointx, pointy, Sample, nvalues, value, ColorSpec, rgba, MarkerShape, outline,
       Plot, draw!, datalimits, setcolor!,
       Figure, Axis, Lines, Scatter, Bars, VLines, Poly, Labels, Stairs, Hist, Band, Canvas, Transform2D,
       add_lines!, add_scatter!, add_bars!, add_vlines!, add_poly!, add_labels!, add_stairs!, add_hist!, add_band!,
       add_plot!, render_png, newfigure, recolor!, NAMED, MARKERS

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

"Values a histogram bins, by index."
@trait Sample begin
    nvalues(s::Sample)::Int
    value(s::Sample, i::Int)::Float64
end
@implement Sample A where {A <: Vector{<:Real}} begin
    nvalues(s) = length(s)
    value(s, i) = Float64(s[i])
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
@implement ColorSpec Vector{Symbol} begin
    rgba(c, i) = get(NAMED, c[i], (0.0, 0.0, 0.0, 1.0))
end

"A marker's outline for point `i`: a closed polygon around (0, 0) of radius about 1, in pixels' orientation (y down)."
@trait MarkerShape begin
    outline(m::MarkerShape, i::Int)::Vector{NTuple{2,Float64}}
end
const MARKERS = Dict{Symbol,Vector{NTuple{2,Float64}}}(
    :circle => [(cos(2pi * k / 32), sin(2pi * k / 32)) for k in 0:31],
    :rect => [(-0.85, -0.85), (0.85, -0.85), (0.85, 0.85), (-0.85, 0.85)],
    :diamond => [(0.0, -1.2), (1.2, 0.0), (0.0, 1.2), (-1.2, 0.0)],
    :utriangle => [(0.0, -1.2), (1.1, 0.8), (-1.1, 0.8)],
    :cross => [(-0.35, -1.0), (0.35, -1.0), (0.35, -0.35), (1.0, -0.35), (1.0, 0.35), (0.35, 0.35),
               (0.35, 1.0), (-0.35, 1.0), (-0.35, 0.35), (-1.0, 0.35), (-1.0, -0.35), (-0.35, -0.35)])
@implement MarkerShape Symbol begin
    outline(m, i) = get(MARKERS, m, MARKERS[:circle])
end
@implement MarkerShape Vector{Symbol} begin
    outline(m, i) = get(MARKERS, m[i], MARKERS[:circle])
end

# --- the canvas: Cairo's surface and context, and the transform from data to pixels ------------------

"Where a plot draws: a Cairo image surface and its context."
struct Canvas
    surface::Cairo.CairoSurfaceBase{UInt32}
    ctx::Cairo.CairoContext
    width::Int
    height::Int
end

"Data to pixels: an affine map per axis (pixel y grows downwards), and the plot area's top and bottom in pixels."
struct Transform2D
    ax::Float64
    bx::Float64
    ay::Float64
    by::Float64
    top::Float64
    bottom::Float64
end
@inline px(t::Transform2D, x::Float64) = t.ax * x + t.bx
@inline py(t::Transform2D, y::Float64) = t.ay * y + t.by

# the backend's primitives, calling Cairo.jl directly
function newcanvas(w::Int, h::Int)
    s = Cairo.CairoARGBSurface(w, h)
    return Canvas(s, Cairo.CairoContext(s), w, h)
end
function polyline!(c::Canvas, xs::Vector{Float64}, ys::Vector{Float64}, col::NTuple{4,Float64}, lw::Float64)
    isempty(xs) && return nothing
    ctx = c.ctx
    Cairo.set_source_rgba(ctx, col[1], col[2], col[3], col[4])
    Cairo.set_line_width(ctx, lw)
    Cairo.move_to(ctx, xs[1], ys[1])
    for i in 2:length(xs)
        Cairo.line_to(ctx, xs[i], ys[i])
    end
    Cairo.stroke(ctx)
    return nothing
end
"A filled polygon through the pixel points (closed)."
function polygon!(c::Canvas, xs::Vector{Float64}, ys::Vector{Float64}, col::NTuple{4,Float64})
    length(xs) < 3 && return nothing
    ctx = c.ctx
    Cairo.set_source_rgba(ctx, col[1], col[2], col[3], col[4])
    Cairo.move_to(ctx, xs[1], ys[1])
    for i in 2:length(xs)
        Cairo.line_to(ctx, xs[i], ys[i])
    end
    Cairo.close_path(ctx)
    Cairo.fill(ctx)
    return nothing
end
function text!(c::Canvas, x::Float64, y::Float64, s::String, size::Float64, halign::Symbol, col::NTuple{4,Float64})
    ctx = c.ctx
    Cairo.set_source_rgba(ctx, col[1], col[2], col[3], col[4])
    Cairo.select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
    Cairo.set_font_size(ctx, size)
    ext = Cairo.text_extents(ctx, s)
    dx = halign === :center ? -ext[3] / 2 : halign === :right ? -ext[3] : 0.0
    Cairo.move_to(ctx, x + dx, y)
    Cairo.show_text(ctx, s)
    return nothing
end
"Text centred at (x, y), turned a quarter anticlockwise (a y label)."
function vtext!(c::Canvas, x::Float64, y::Float64, s::String, size::Float64)
    ctx = c.ctx
    Cairo.save(ctx)
    Cairo.translate(ctx, x, y)
    Cairo.rotate(ctx, -pi / 2)
    text!(c, 0.0, 0.0, s, size, :center, (0.0, 0.0, 0.0, 1.0))
    Cairo.restore(ctx)
    return nothing
end
function fillrect!(c::Canvas, x::Float64, y::Float64, w::Float64, h::Float64, col::NTuple{4,Float64})
    ctx = c.ctx
    Cairo.set_source_rgba(ctx, col[1], col[2], col[3], col[4])
    Cairo.rectangle(ctx, x, y, w, h)
    Cairo.fill(ctx)
    return nothing
end
writepng(c::Canvas, path::String) = (Cairo.write_to_png(c.surface, path); nothing)

# --- plots: a recipe trait ----------------------------------------------------------------------

"A recipe: its data limits, how it draws itself onto a canvas, and its colour, which may change shape."
@trait Plot begin
    datalimits(p::Plot)::NTuple{4,Float64}
    draw!(p::Plot, c::Canvas, t::Transform2D)::Nothing
    setcolor!(p::Plot, c::Dynamic{ColorSpec})::Nothing
end

# the loops over data: bounded functions; the plots hold their data as `Dynamic` fields, so the plots'
# implementations pass them with `compiled_for`, and each loop runs compiled for the data's key
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

# --- primitives ---------------------------------------------------------------------------------

"Lines through points. Its data and colour are kept as dynamic values: any conforming type."
mutable struct Lines
    pos::Positions                  # a trait's name in a field: Dynamic{Positions}
    color::ColorSpec                # Dynamic{ColorSpec}
    linewidth::Float64
end
"Markers at points: a shape (one, or one per point) and a colour (one, or one per point)."
mutable struct Scatter
    pos::Positions
    color::ColorSpec
    markersize::Float64
    marker::MarkerShape             # Dynamic{MarkerShape}
end
"Bars from zero to each point's y, centred at its x."
mutable struct Bars
    pos::Positions
    color::ColorSpec
    width::Float64                  # in data units
end
"Vertical lines at the points' x across the plot area (their y is ignored)."
mutable struct VLines
    pos::Positions
    color::ColorSpec
    linewidth::Float64
end
"A filled polygon through the points (its first colour)."
mutable struct Poly
    pos::Positions
    color::ColorSpec
end
"Text at points: `texts[i]` at point `i`, aligned left, centre or right."
mutable struct Labels
    pos::Positions
    texts::Vector{String}
    color::ColorSpec
    fontsize::Float64
    align::Symbol
end

"Markers of shape `m`, radius `r` pixels, at the pixel points."
function drawmarkers(m::MarkerShape, c::Canvas, xs::Vector{Float64}, ys::Vector{Float64}, cols::Vector{NTuple{4,Float64}}, r::Float64)
    ctx = c.ctx
    for i in eachindex(xs)
        o = outline(m, i)
        isempty(o) && continue
        col = cols[i]
        Cairo.set_source_rgba(ctx, col[1], col[2], col[3], col[4])
        Cairo.move_to(ctx, xs[i] + r * o[1][1], ys[i] + r * o[1][2])
        for k in 2:length(o)
            Cairo.line_to(ctx, xs[i] + r * o[k][1], ys[i] + r * o[k][2])
        end
        Cairo.close_path(ctx)
        Cairo.fill(ctx)
    end
    return nothing
end
function barlimits(pos::Positions, w::Float64)
    xmin, xmax, ymin, ymax = limits(pos)
    return (xmin - w / 2, xmax + w / 2, min(ymin, 0.0), max(ymax, 0.0))
end
function drawbars(pos::Positions, c::Canvas, t::Transform2D, col::ColorSpec, w::Float64)
    for i in 1:npoints(pos)
        x, y = pointx(pos, i), pointy(pos, i)
        x0, x1 = px(t, x - w / 2), px(t, x + w / 2)
        y0, y1 = py(t, 0.0), py(t, y)
        fillrect!(c, x0, min(y0, y1), x1 - x0, abs(y1 - y0), rgba(col, i))
    end
    return nothing
end
function vlimits(pos::Positions)
    xmin, xmax, _, _ = limits(pos)
    return (xmin, xmax, Inf, -Inf)                  # no extent in y
end
function drawvlines(pos::Positions, c::Canvas, t::Transform2D, col::ColorSpec, lw::Float64)
    for i in 1:npoints(pos)
        x = px(t, pointx(pos, i))
        polyline!(c, [x, x], [t.top, t.bottom], rgba(col, i), lw)
    end
    return nothing
end
function drawlabels(pos::Positions, c::Canvas, t::Transform2D, texts::Vector{String}, col::ColorSpec, size::Float64, align::Symbol)
    for i in 1:min(npoints(pos), length(texts))
        text!(c, px(t, pointx(pos, i)), py(t, pointy(pos, i)), texts[i], size, align, rgba(col, i))
    end
    return nothing
end

# opening a dynamic value at a bound selects the worker by dispatch: the result is asserted here
datalimits(p::Lines) = limits(compiled_for(p.pos))::NTuple{4,Float64}
datalimits(p::Scatter) = limits(compiled_for(p.pos))::NTuple{4,Float64}
datalimits(p::Bars) = barlimits(compiled_for(p.pos), p.width)::NTuple{4,Float64}
datalimits(p::VLines) = vlimits(compiled_for(p.pos))::NTuple{4,Float64}
datalimits(p::Poly) = limits(compiled_for(p.pos))::NTuple{4,Float64}
datalimits(p::Labels) = limits(compiled_for(p.pos))::NTuple{4,Float64}
function draw!(p::Lines, c::Canvas, t::Transform2D)
    xs, ys = pixels(compiled_for(p.pos), t)::Tuple{Vector{Float64},Vector{Float64}}
    polyline!(c, xs, ys, rgba(p.color, 1), p.linewidth)
    return nothing
end
function draw!(p::Scatter, c::Canvas, t::Transform2D)
    xs, ys = pixels(compiled_for(p.pos), t)::Tuple{Vector{Float64},Vector{Float64}}
    drawmarkers(compiled_for(p.marker), c, xs, ys, colors(compiled_for(p.color), length(xs))::Vector{NTuple{4,Float64}}, p.markersize / 2)::Nothing
    return nothing
end
draw!(p::Bars, c::Canvas, t::Transform2D) = drawbars(compiled_for(p.pos), c, t, compiled_for(p.color), p.width)::Nothing
draw!(p::VLines, c::Canvas, t::Transform2D) = drawvlines(compiled_for(p.pos), c, t, compiled_for(p.color), p.linewidth)::Nothing
function draw!(p::Poly, c::Canvas, t::Transform2D)
    xs, ys = pixels(compiled_for(p.pos), t)::Tuple{Vector{Float64},Vector{Float64}}
    polygon!(c, xs, ys, rgba(p.color, 1))
    return nothing
end
draw!(p::Labels, c::Canvas, t::Transform2D) = drawlabels(compiled_for(p.pos), c, t, p.texts, compiled_for(p.color), p.fontsize, p.align)::Nothing
setcolor!(p::Lines, c::Dynamic{ColorSpec}) = (p.color = c; nothing)
setcolor!(p::Scatter, c::Dynamic{ColorSpec}) = (p.color = c; nothing)
setcolor!(p::Bars, c::Dynamic{ColorSpec}) = (p.color = c; nothing)
setcolor!(p::VLines, c::Dynamic{ColorSpec}) = (p.color = c; nothing)
setcolor!(p::Poly, c::Dynamic{ColorSpec}) = (p.color = c; nothing)
setcolor!(p::Labels, c::Dynamic{ColorSpec}) = (p.color = c; nothing)
@implement Plot Lines
@implement Plot Scatter
@implement Plot Bars
@implement Plot VLines
@implement Plot Poly
@implement Plot Labels

# --- recipes with children: a recipe keeps its own data and attributes, and rebuilds its children
#     from them before each use (`refresh!`), so a child follows the parent's attributes and a live
#     source; the children are the library's primitives, drawn by their own methods -----------------

"A step line through points: `step` is `:pre`, `:post` or `:center`. Its child is a `Lines` through the steps."
mutable struct Stairs
    pos::Positions
    step::Symbol
    color::ColorSpec
    linewidth::Float64
    line::Lines                     # the child
end
"A histogram of a sample in `bins` equal bins. Its child is a `Bars` of the counts."
mutable struct Hist
    values::Sample                  # Dynamic{Sample}
    bins::Int
    color::ColorSpec
    bars::Bars                      # the child
end
"A band between two curves, `lower` and `upper` (in order of x). Its child is a `Poly` of the outline."
mutable struct Band
    lower::Positions
    upper::Positions
    color::ColorSpec
    poly::Poly                      # the child
end

"The step points of `pos` (Makie's `stairs`), as an n × 2 matrix."
function steppoints(pos::Positions, step::Symbol)
    n = npoints(pos)
    n == 0 && return Matrix{Float64}(undef, 0, 2)
    m = step === :center ? 2n : 2n - 1
    out = Matrix{Float64}(undef, m, 2)
    out[1, 1], out[1, 2] = pointx(pos, 1), pointy(pos, 1)
    for i in 1:n-1
        x0, y0, x1, y1 = pointx(pos, i), pointy(pos, i), pointx(pos, i + 1), pointy(pos, i + 1)
        if step === :pre
            out[2i, 1], out[2i, 2] = x0, y1
            out[2i+1, 1], out[2i+1, 2] = x1, y1
        elseif step === :post
            out[2i, 1], out[2i, 2] = x1, y0
            out[2i+1, 1], out[2i+1, 2] = x1, y1
        else
            h = (x0 + x1) / 2
            out[2i, 1], out[2i, 2] = h, y0
            out[2i+1, 1], out[2i+1, 2] = h, y1
        end
    end
    step === :center && ((out[m, 1], out[m, 2]) = (pointx(pos, n), pointy(pos, n)))
    return out
end
"Bin centres and counts of a sample (an n × 2 matrix), and the bins' width."
function binned(s::Sample, bins::Int)
    n = nvalues(s)
    n == 0 && return Matrix{Float64}(undef, 0, 2), 1.0
    lo, hi = Inf, -Inf
    for i in 1:n
        v = value(s, i)
        lo = min(lo, v); hi = max(hi, v)
    end
    w = hi > lo ? (hi - lo) / bins : 1.0
    counts = zeros(bins)
    for i in 1:n
        counts[clamp(floor(Int, (value(s, i) - lo) / w) + 1, 1, bins)] += 1
    end
    out = Matrix{Float64}(undef, bins, 2)
    for k in 1:bins
        out[k, 1], out[k, 2] = lo + (k - 0.5) * w, counts[k]
    end
    return out, w
end
"The band's outline: the lower curve, then the upper curve backwards."
function bandoutline(lo::Positions, up::Positions)
    n, m = npoints(lo), npoints(up)
    out = Matrix{Float64}(undef, n + m, 2)
    for i in 1:n
        out[i, 1], out[i, 2] = pointx(lo, i), pointy(lo, i)
    end
    for j in 1:m
        out[n+j, 1], out[n+j, 2] = pointx(up, m - j + 1), pointy(up, m - j + 1)
    end
    return out
end

function refresh!(s::Stairs)
    s.step in (:pre, :post, :center) || throw(ArgumentError("stairs: step is :pre, :post or :center, not :$(s.step)"))
    l = s.line
    l.pos = Dynamic{Positions}(steppoints(compiled_for(s.pos), s.step)::Matrix{Float64})
    l.color = s.color
    l.linewidth = s.linewidth
    return l
end
function refresh!(h::Hist)
    h.bins >= 1 || throw(ArgumentError("hist: bins must be at least 1, not $(h.bins)"))
    pts, w = binned(compiled_for(h.values), h.bins)::Tuple{Matrix{Float64},Float64}
    b = h.bars
    b.pos = Dynamic{Positions}(pts)
    b.width = w
    b.color = h.color
    return b
end
function refresh!(b::Band)
    p = b.poly
    p.pos = Dynamic{Positions}(bandoutline(compiled_for(b.lower), compiled_for(b.upper))::Matrix{Float64})
    p.color = b.color
    return p
end
datalimits(s::Stairs) = datalimits(refresh!(s))
datalimits(h::Hist) = datalimits(refresh!(h))
datalimits(b::Band) = datalimits(refresh!(b))
draw!(s::Stairs, c::Canvas, t::Transform2D) = draw!(refresh!(s), c, t)
draw!(h::Hist, c::Canvas, t::Transform2D) = draw!(refresh!(h), c, t)
draw!(b::Band, c::Canvas, t::Transform2D) = draw!(refresh!(b), c, t)
setcolor!(s::Stairs, c::Dynamic{ColorSpec}) = (s.color = c; nothing)
setcolor!(h::Hist, c::Dynamic{ColorSpec}) = (h.color = c; nothing)
setcolor!(b::Band, c::Dynamic{ColorSpec}) = (b.color = c; nothing)
@implement Plot Stairs
@implement Plot Hist
@implement Plot Band

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

newfigure(width::Int, height::Int, title::String, xlabel::String, ylabel::String) =
    Figure(width, height, Axis(Dynamic{Plot}[], title, xlabel, ylabel))
newfigure(width::Int, height::Int, title::String) = newfigure(width, height, title, "", "")

"Add a plot of any conforming type (a user's recipe) to the figure."
add_plot!(f::Figure, p::Plot) = (push!(f.axis.plots, Dynamic{Plot}(p)); nothing)
# the library's recipes, made from bounded arguments; each returns the plot, kept in the axis
function add_lines!(f::Figure, pos::Positions, color::ColorSpec, linewidth::Float64)
    p = Lines(Dynamic{Positions}(pos), Dynamic{ColorSpec}(color), linewidth)
    push!(f.axis.plots, Dynamic{Plot}(p))
    return p
end
function add_scatter!(f::Figure, pos::Positions, color::ColorSpec, markersize::Float64, marker::MarkerShape)
    p = Scatter(Dynamic{Positions}(pos), Dynamic{ColorSpec}(color), markersize, Dynamic{MarkerShape}(marker))
    push!(f.axis.plots, Dynamic{Plot}(p))
    return p
end
function add_bars!(f::Figure, pos::Positions, color::ColorSpec, width::Float64)
    p = Bars(Dynamic{Positions}(pos), Dynamic{ColorSpec}(color), width)
    push!(f.axis.plots, Dynamic{Plot}(p))
    return p
end
function add_vlines!(f::Figure, pos::Positions, color::ColorSpec, linewidth::Float64)
    p = VLines(Dynamic{Positions}(pos), Dynamic{ColorSpec}(color), linewidth)
    push!(f.axis.plots, Dynamic{Plot}(p))
    return p
end
function add_poly!(f::Figure, pos::Positions, color::ColorSpec)
    p = Poly(Dynamic{Positions}(pos), Dynamic{ColorSpec}(color))
    push!(f.axis.plots, Dynamic{Plot}(p))
    return p
end
function add_labels!(f::Figure, pos::Positions, texts::Vector{String}, color::ColorSpec, fontsize::Float64, align::Symbol)
    p = Labels(Dynamic{Positions}(pos), texts, Dynamic{ColorSpec}(color), fontsize, align)
    push!(f.axis.plots, Dynamic{Plot}(p))
    return p
end
const NOPOINTS = Matrix{Float64}(undef, 0, 2)
function add_stairs!(f::Figure, pos::Positions, step::Symbol, color::ColorSpec, linewidth::Float64)
    c = Dynamic{ColorSpec}(color)
    p = Stairs(Dynamic{Positions}(pos), step, c, linewidth, Lines(Dynamic{Positions}(NOPOINTS), c, linewidth))
    push!(f.axis.plots, Dynamic{Plot}(p))
    return p
end
function add_hist!(f::Figure, values::Sample, bins::Int, color::ColorSpec)
    c = Dynamic{ColorSpec}(color)
    p = Hist(Dynamic{Sample}(values), bins, c, Bars(Dynamic{Positions}(NOPOINTS), c, 1.0))
    push!(f.axis.plots, Dynamic{Plot}(p))
    return p
end
function add_band!(f::Figure, lower::Positions, upper::Positions, color::ColorSpec)
    c = Dynamic{ColorSpec}(color)
    p = Band(Dynamic{Positions}(lower), Dynamic{Positions}(upper), c, Poly(Dynamic{Positions}(NOPOINTS), c))
    push!(f.axis.plots, Dynamic{Plot}(p))
    return p
end

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
    c = newcanvas(W, H)
    fillrect!(c, 0.0, 0.0, Float64(W), Float64(H), (1.0, 1.0, 1.0, 1.0))
    ax = f.axis
    xmin, xmax, ymin, ymax = Inf, -Inf, Inf, -Inf
    for p in ax.plots
        l = datalimits(p)                              # one dispatch per plot
        xmin = min(xmin, l[1]); xmax = max(xmax, l[2]); ymin = min(ymin, l[3]); ymax = max(ymax, l[4])
    end
    if !isfinite(xmin) || !isfinite(xmax)
        xmin, xmax = 0.0, 1.0
    end
    if !isfinite(ymin) || !isfinite(ymax)
        ymin, ymax = 0.0, 1.0
    end
    dx, dy = 0.05 * max(xmax - xmin, 1e-12), 0.05 * max(ymax - ymin, 1e-12)
    xmin -= dx; xmax += dx; ymin -= dy; ymax += dy
    l, r, top, b = 60.0, W - 20.0, 40.0, H - 40.0     # the plot area
    t = Transform2D((r - l) / (xmax - xmin), l - (r - l) / (xmax - xmin) * xmin,
                    -(b - top) / (ymax - ymin), b + (b - top) / (ymax - ymin) * ymin, top, b)
    black, gray = (0.0, 0.0, 0.0, 1.0), (0.85, 0.85, 0.85, 1.0)
    for v in ticks(xmin, xmax, 6)
        polyline!(c, [px(t, v), px(t, v)], [top, b], gray, 0.5)
        text!(c, px(t, v), b + 16.0, ticklabel(v), 11.0, :center, black)
    end
    for v in ticks(ymin, ymax, 5)
        polyline!(c, [l, r], [py(t, v), py(t, v)], gray, 0.5)
        text!(c, l - 6.0, py(t, v) + 4.0, ticklabel(v), 11.0, :right, black)
    end
    polyline!(c, [l, r, r, l, l], [top, top, b, b, top], black, 1.0)
    isempty(ax.title) || text!(c, (l + r) / 2, 24.0, ax.title, 14.0, :center, black)
    isempty(ax.xlabel) || text!(c, (l + r) / 2, H - 8.0, ax.xlabel, 12.0, :center, black)
    isempty(ax.ylabel) || vtext!(c, 14.0, (top + b) / 2, ax.ylabel, 12.0)
    for p in ax.plots
        draw!(p, c, t)                                 # one dispatch per plot; its loops run compiled per key
    end
    writepng(c, path)
    return nothing
end

end

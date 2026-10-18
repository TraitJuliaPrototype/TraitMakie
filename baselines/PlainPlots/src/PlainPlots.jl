"""
    PlainPlots

TraitMakie without traits (its README's baseline `PlainPlots`): the same algorithms, canvas and
interface, written as Makie is: a plot is a kind and a `Dict{Symbol, Any}` of attributes (read and
set as properties, `p.color = :red`), an axis holds `Vector{Any}` plots, and each drawing loop runs
behind a function barrier, compiled per data and colour type. A user's data type supplies
`PlainPlots.points(d)` (an n × 2 matrix or a vector of pairs) or `PlainPlots.samples(d)` (a vector of
numbers); a user's colour supplies `PlainPlots.rgba(c, i)`, a user's marker `PlainPlots.outline(m, i)`,
a user's recipe `PlainPlots.datalimits(p)` and `PlainPlots.draw!(p, canvas, transform)`.
"""
module PlainPlots
using Cairo: Cairo
using PrecompileTools: @compile_workload
export lines, lines!, scatter, scatter!, barplot, barplot!, hist, hist!, vlines!, stairs, stairs!, band, band!,
       poly, poly!, text!, plot!, save, figure, recolor!, Live, onchange

const NAMED = Dict{Symbol,NTuple{4,Float64}}(
    :black => (0.0, 0.0, 0.0, 1.0), :white => (1.0, 1.0, 1.0, 1.0), :red => (0.85, 0.15, 0.15, 1.0),
    :green => (0.15, 0.6, 0.2, 1.0), :blue => (0.12, 0.35, 0.8, 1.0), :orange => (0.95, 0.55, 0.1, 1.0),
    :gray => (0.5, 0.5, 0.5, 1.0), :purple => (0.5, 0.2, 0.65, 1.0))
rgba(c::Symbol, i::Int) = get(NAMED, c, (0.0, 0.0, 0.0, 1.0))
rgba(c::NTuple{4,Float64}, i::Int) = c
rgba(c::Vector{NTuple{4,Float64}}, i::Int) = c[i]
rgba(c::Vector{Symbol}, i::Int) = get(NAMED, c[i], (0.0, 0.0, 0.0, 1.0))
const MARKERS = Dict{Symbol,Vector{NTuple{2,Float64}}}(
    :circle => [(cos(2pi * k / 32), sin(2pi * k / 32)) for k in 0:31],
    :rect => [(-0.85, -0.85), (0.85, -0.85), (0.85, 0.85), (-0.85, 0.85)],
    :diamond => [(0.0, -1.2), (1.2, 0.0), (0.0, 1.2), (-1.2, 0.0)],
    :utriangle => [(0.0, -1.2), (1.1, 0.8), (-1.1, 0.8)],
    :cross => [(-0.35, -1.0), (0.35, -1.0), (0.35, -0.35), (1.0, -0.35), (1.0, 0.35), (0.35, 0.35),
               (0.35, 1.0), (-0.35, 1.0), (-0.35, 0.35), (-1.0, 0.35), (-1.0, -0.35), (-0.35, -0.35)])
outline(m::Symbol, i::Int) = get(MARKERS, m, MARKERS[:circle])
outline(m::Vector{Symbol}, i::Int) = get(MARKERS, m[i], MARKERS[:circle])
nvalues(s::AbstractVector{<:Real}) = length(s)
value(s::AbstractVector{<:Real}, i::Int) = Float64(s[i])
npoints(p::AbstractMatrix) = size(p, 1)
pointx(p::AbstractMatrix, i::Int) = Float64(p[i, 1])
pointy(p::AbstractMatrix, i::Int) = Float64(p[i, 2])
npoints(p::AbstractVector{<:Tuple}) = length(p)
pointx(p::AbstractVector{<:Tuple}, i::Int) = Float64(p[i][1])
pointy(p::AbstractVector{<:Tuple}, i::Int) = Float64(p[i][2])
"A user's data: its points as a matrix or a vector of pairs."
points(d) = d
"A user's sample: its values as a vector of numbers."
samples(d) = d

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
function canvas_text!(c::Canvas, x::Float64, y::Float64, s::String, size::Float64, halign::Symbol, col::NTuple{4,Float64})
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
    canvas_text!(c, 0.0, 0.0, s, size, :center, (0.0, 0.0, 0.0, 1.0))
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


# --- plots: a kind and attributes, as Makie stores them ----------------------------------------

mutable struct PlotObj
    kind::Symbol
    attributes::Dict{Symbol,Any}
end
"Attributes as properties, as in Makie: `p.color`, `p.color = :red` (checked as at the call that made the plot)."
Base.getproperty(p::PlotObj, name::Symbol) = getfield(p, :attributes)[name]
Base.setproperty!(p::PlotObj, name::Symbol, x) = (getfield(p, :attributes)[name] = _attr(name, x); x)
Base.propertynames(p::PlotObj) = Tuple(keys(getfield(p, :attributes)))
kind(p::PlotObj) = getfield(p, :kind)
attrs(p::PlotObj) = getfield(p, :attributes)
mutable struct Axis
    plots::Vector{Any}
    title::String
    xlabel::String
    ylabel::String
end
struct Figure
    width::Int
    height::Int
    axis::Axis
end

function limits(pos)
    xmin, xmax, ymin, ymax = Inf, -Inf, Inf, -Inf
    for i in 1:npoints(pos)
        x, y = pointx(pos, i), pointy(pos, i)
        xmin = min(xmin, x); xmax = max(xmax, x); ymin = min(ymin, y); ymax = max(ymax, y)
    end
    return (xmin, xmax, ymin, ymax)
end
function pixels(pos, t::Transform2D)
    n = npoints(pos)
    xs = Vector{Float64}(undef, n); ys = Vector{Float64}(undef, n)
    for i in 1:n
        xs[i] = px(t, pointx(pos, i)); ys[i] = py(t, pointy(pos, i))
    end
    return xs, ys
end
colors(c, n::Int) = NTuple{4,Float64}[rgba(c, i) for i in 1:n]
function drawmarkers(m, c::Canvas, xs::Vector{Float64}, ys::Vector{Float64}, cols::Vector{NTuple{4,Float64}}, r::Float64)
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
function drawbars(pos, c::Canvas, t::Transform2D, col, w::Float64)
    for i in 1:npoints(pos)
        x, y = pointx(pos, i), pointy(pos, i)
        x0, x1 = px(t, x - w / 2), px(t, x + w / 2)
        y0, y1 = py(t, 0.0), py(t, y)
        fillrect!(c, x0, min(y0, y1), x1 - x0, abs(y1 - y0), rgba(col, i))
    end
end
function drawvlines(pos, c::Canvas, t::Transform2D, col, lw::Float64)
    for i in 1:npoints(pos)
        x = px(t, pointx(pos, i))
        polyline!(c, [x, x], [t.top, t.bottom], rgba(col, i), lw)
    end
end
function drawlabels(pos, c::Canvas, t::Transform2D, texts::Vector{String}, col, size::Float64, align::Symbol)
    for i in 1:min(npoints(pos), length(texts))
        canvas_text!(c, px(t, pointx(pos, i)), py(t, pointy(pos, i)), texts[i], size, align, rgba(col, i))
    end
end

# the composite kinds: derived points, computed at each render from the plot's attributes
"The step points of `pos` (Makie's `stairs`), as an n × 2 matrix."
function steppoints(pos, step::Symbol)
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
function binned(s, bins::Int)
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
function bandoutline(lo, up)
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
function _histbars(a)
    a[:bins] >= 1 || throw(ArgumentError("hist: bins must be at least 1, not $(a[:bins])"))
    return binned(samples(a[:values]), a[:bins]::Int)
end
function _stairpoints(a)
    a[:step] in (:pre, :post, :center) || throw(ArgumentError("stairs: step is :pre, :post or :center, not :$(a[:step])"))
    return steppoints(points(a[:pos]), a[:step])
end

function datalimits(p::PlotObj)
    a = attrs(p)
    k = kind(p)
    if k === :hist
        pts, w = _histbars(a)
        xmin, xmax, ymin, ymax = limits(pts)
        return (xmin - w / 2, xmax + w / 2, min(ymin, 0.0), max(ymax, 0.0))
    elseif k === :stairs
        return limits(_stairpoints(a))
    elseif k === :band
        return limits(bandoutline(points(a[:lower]), points(a[:upper])))
    end
    pos = points(a[:pos])
    if k === :bars
        w = a[:width]::Float64
        xmin, xmax, ymin, ymax = limits(pos)
        return (xmin - w / 2, xmax + w / 2, min(ymin, 0.0), max(ymax, 0.0))
    elseif k === :vlines
        xmin, xmax, _, _ = limits(pos)
        return (xmin, xmax, Inf, -Inf)
    end
    return limits(pos)
end
function draw!(p::PlotObj, c::Canvas, t::Transform2D)
    a = attrs(p)
    k = kind(p)
    col = a[:color]
    if k === :hist
        pts, w = _histbars(a)
        drawbars(pts, c, t, col, w)
        return nothing
    elseif k === :stairs
        xs, ys = pixels(_stairpoints(a), t)
        polyline!(c, xs, ys, rgba(col, 1), a[:linewidth]::Float64)
        return nothing
    elseif k === :band
        xs, ys = pixels(bandoutline(points(a[:lower]), points(a[:upper])), t)
        polygon!(c, xs, ys, rgba(col, 1))
        return nothing
    end
    pos = points(a[:pos])
    if k === :lines
        xs, ys = pixels(pos, t)
        polyline!(c, xs, ys, rgba(col, 1), a[:linewidth]::Float64)
    elseif k === :scatter
        xs, ys = pixels(pos, t)
        drawmarkers(a[:marker], c, xs, ys, colors(col, length(xs)), (a[:markersize]::Float64) / 2)
    elseif k === :bars
        drawbars(pos, c, t, col, a[:width]::Float64)
    elseif k === :poly
        xs, ys = pixels(pos, t)
        polygon!(c, xs, ys, rgba(col, 1))
    elseif k === :labels
        drawlabels(pos, c, t, a[:texts]::Vector{String}, col, a[:fontsize]::Float64, a[:align]::Symbol)
    else
        drawvlines(pos, c, t, col, a[:linewidth]::Float64)
    end
    return nothing
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
        l = datalimits(p)::NTuple{4,Float64}
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
    l, r, top, b = 60.0, W - 20.0, 40.0, H - 40.0
    t = Transform2D((r - l) / (xmax - xmin), l - (r - l) / (xmax - xmin) * xmin,
                    -(b - top) / (ymax - ymin), b + (b - top) / (ymax - ymin) * ymin, top, b)
    black, gray = (0.0, 0.0, 0.0, 1.0), (0.85, 0.85, 0.85, 1.0)
    for v in ticks(xmin, xmax, 6)
        polyline!(c, [px(t, v), px(t, v)], [top, b], gray, 0.5)
        canvas_text!(c, px(t, v), b + 16.0, ticklabel(v), 11.0, :center, black)
    end
    for v in ticks(ymin, ymax, 5)
        polyline!(c, [l, r], [py(t, v), py(t, v)], gray, 0.5)
        canvas_text!(c, l - 6.0, py(t, v) + 4.0, ticklabel(v), 11.0, :right, black)
    end
    polyline!(c, [l, r, r, l, l], [top, top, b, b, top], black, 1.0)
    isempty(ax.title) || canvas_text!(c, (l + r) / 2, 24.0, ax.title, 14.0, :center, black)
    isempty(ax.xlabel) || canvas_text!(c, (l + r) / 2, H - 8.0, ax.xlabel, 12.0, :center, black)
    isempty(ax.ylabel) || vtext!(c, 14.0, (top + b) / 2, ax.ylabel, 12.0)
    for p in ax.plots
        draw!(p, c, t)
    end
    writepng(c, path)
    return nothing
end

# --- names, checked where they are given (the same messages as TraitMakie's) ------------------------

_names(d) = join((":" * string(k) for k in sort!(collect(keys(d)))), ", ")
function _named(c::Symbol)
    haskey(NAMED, c) && return c
    throw(ArgumentError("unknown colour :$c. The named colours are $(_names(NAMED)); a colour may also be an RGB or RGBA tuple, a vector of colours (one per point), or a value of a type with a method of PlainPlots.rgba"))
end
_color(c::Symbol) = _named(c)
_color(c::NTuple{4,<:Real}) = NTuple{4,Float64}(c)
_color(c::NTuple{3,<:Real}) = (Float64(c[1]), Float64(c[2]), Float64(c[3]), 1.0)
_color(c::AbstractVector{Symbol}) = Symbol[_named(s) for s in c]
_color(c::AbstractVector{<:Tuple}) = NTuple{4,Float64}[_color(x) for x in c]
_color(c) = c
function _mark(m::Symbol)
    haskey(MARKERS, m) && return m
    throw(ArgumentError("unknown marker :$m. The markers are $(_names(MARKERS)), a vector of them (one per point), or a value of a type with a method of PlainPlots.outline"))
end
_marker(m::Symbol) = _mark(m)
_marker(m::AbstractVector{Symbol}) = Symbol[_mark(s) for s in m]
_marker(m) = m
_step(s::Symbol) = s in (:pre, :post, :center) ? s :
    throw(ArgumentError("unknown step :$s. The steps are :pre, :post and :center"))
_bins(b::Integer) = b >= 1 ? Int(b) : throw(ArgumentError("bins must be at least 1, not $b"))
_align(a::Symbol) = a in (:left, :center, :right) ? a :
    throw(ArgumentError("unknown alignment :$a. The alignments are :left, :center and :right"))
_xy(x::AbstractVector, y::AbstractVector) =
    length(x) == length(y) ? hcat(Vector{Float64}(x), Vector{Float64}(y)) :
    throw(DimensionMismatch("x has $(length(x)) values, y has $(length(y))"))
_sample(x::Vector{<:Real}) = x
_sample(x::AbstractVector{<:Real}) = Vector{Float64}(x)
_sample(x) = x
"An attribute's value as the call that made the plot takes it."
function _attr(name::Symbol, x)
    name === :color && return _color(x)
    name === :marker && return _marker(x)
    name === :step && return _step(x)
    name === :bins && return _bins(x)
    name === :align && return _align(x)
    name === :values && return _sample(x)
    name in (:pos, :lower, :upper) && x isa Tuple{AbstractVector,AbstractVector} && return _xy(x[1], x[2])
    name in (:linewidth, :markersize, :width, :fontsize) && return Float64(x)
    return x
end

# --- the interface, as TraitMakie's ------------------------------------------------------------

figure(; size = (600, 400), title = "", xlabel = "", ylabel = "") =
    Figure(Int(size[1]), Int(size[2]), Axis(Any[], String(title), String(xlabel), String(ylabel)))
_add!(fig, kind; kw...) = (p = PlotObj(kind, Dict{Symbol,Any}(kw...)); push!(fig.axis.plots, p); p)
lines!(fig::Figure, x::AbstractVector, y::AbstractVector; kw...) = lines!(fig, _xy(x, y); kw...)
lines!(fig::Figure, data; color = :blue, linewidth = 1.5) = _add!(fig, :lines; pos = data, color = _color(color), linewidth = Float64(linewidth))
scatter!(fig::Figure, x::AbstractVector, y::AbstractVector; kw...) = scatter!(fig, _xy(x, y); kw...)
scatter!(fig::Figure, data; color = :black, markersize = 6, marker = :circle) =
    _add!(fig, :scatter; pos = data, color = _color(color), markersize = Float64(markersize), marker = _marker(marker))
_gap(x) = length(x) < 2 ? 1.0 : 0.8 * minimum(diff(sort(Vector{Float64}(x))))
barplot!(fig::Figure, x::AbstractVector, y::AbstractVector; color = :blue, width = nothing) =
    _add!(fig, :bars; pos = _xy(x, y), color = _color(color), width = Float64(something(width, _gap(x))))
hist!(fig::Figure, x; bins::Integer = 10, color = :blue) = _add!(fig, :hist; values = _sample(x), bins = _bins(bins), color = _color(color))
vlines!(fig::Figure, xs::AbstractVector; color = :black, linewidth = 1.5) =
    _add!(fig, :vlines; pos = _xy(xs, zeros(length(xs))), color = _color(color), linewidth = Float64(linewidth))
vlines!(fig::Figure, x::Real; kw...) = vlines!(fig, [x]; kw...)
stairs!(fig::Figure, x::AbstractVector, y::AbstractVector; kw...) = stairs!(fig, _xy(x, y); kw...)
stairs!(fig::Figure, data; step = :pre, color = :blue, linewidth = 1.5) =
    _add!(fig, :stairs; pos = data, step = _step(step), color = _color(color), linewidth = Float64(linewidth))
band!(fig::Figure, x::AbstractVector, lower::AbstractVector, upper::AbstractVector; kw...) = band!(fig, _xy(x, lower), _xy(x, upper); kw...)
band!(fig::Figure, lower, upper; color = (0.12, 0.35, 0.8, 0.3)) = _add!(fig, :band; lower, upper, color = _color(color))
poly!(fig::Figure, x::AbstractVector, y::AbstractVector; kw...) = poly!(fig, _xy(x, y); kw...)
poly!(fig::Figure, data; color = :gray) = _add!(fig, :poly; pos = data, color = _color(color))
text!(fig::Figure, x::AbstractVector, y::AbstractVector, texts::AbstractVector; kw...) = text!(fig, _xy(x, y), texts; kw...)
text!(fig::Figure, x::Real, y::Real, s::AbstractString; kw...) = text!(fig, [x], [y], [s]; kw...)
text!(fig::Figure, data, texts::AbstractVector; color = :black, fontsize = 11, align = :left) =
    _add!(fig, :labels; pos = data, texts = String[string(s) for s in texts], color = _color(color), fontsize = Float64(fontsize), align = _align(align))
"Add a user's plot object: its type has methods of `PlainPlots.datalimits` and `PlainPlots.draw!`."
plot!(fig::Figure, p) = (push!(fig.axis.plots, p); p)
for f in (:lines, :scatter, :barplot, :hist, :stairs, :band, :poly)
    f! = Symbol(f, "!")
    @eval $f(args...; title = "", size = (600, 400), xlabel = "", ylabel = "", kw...) =
        (fig = figure(; size, title, xlabel, ylabel); $f!(fig, args...; kw...); fig)
end
recolor!(fig::Figure, k::Integer, color) = (attrs(fig.axis.plots[k])[:color] = _color(color); fig)
save(path::AbstractString, fig::Figure) = (render_png(fig, String(path)); path)

# --- live data: as TraitMakie's ------------------------------------------------------------------

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
onchange(f, l::Live) = (push!(l.listeners, f); f)
points(l::Live) = l.val
samples(l::Live) = l.val

@compile_workload begin
    xs = collect(range(0.0, 2pi; length = 50))
    path = tempname() * ".png"
    f = lines(xs, sin.(xs); title = "workload")
    scatter!(f, xs, cos.(xs); color = [(0.2, 0.4, 0.8, 1.0) for _ in xs])
    scatter!(f, xs, sin.(xs); color = :red, marker = :rect)
    s = scatter!(f, xs, sin.(xs); color = (0.1, 0.2, 0.3), marker = [k % 2 == 0 ? :diamond : :cross for k in eachindex(xs)])
    lines!(f, [(0.0, 0.0), (1.0, 1.0)]; color = (1.0, 0.0, 0.0))
    recolor!(f, 2, :red)
    s.color = [isodd(k) ? :green : :orange for k in eachindex(xs)]
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
    lv = Live([0.0 0.0; 1.0 1.0])
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

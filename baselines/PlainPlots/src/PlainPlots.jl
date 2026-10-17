"""
    PlainPlots

TraitMakie without traits (its README's baseline `PlainPlots`): the same algorithms, canvas and
interface, written as Makie is: a plot is a kind and a `Dict{Symbol, Any}` of attributes, an axis
holds `Vector{Any}` plots, and each drawing loop runs behind a function barrier, compiled per data
and colour type. A user's data type supplies `PlainPlots.points(d)` (an n × 2 matrix or a vector of
pairs); a user's colour supplies `PlainPlots.rgba(c, i)`.
"""
module PlainPlots
using Cairo: Cairo
using PrecompileTools: @compile_workload
export lines, lines!, scatter, scatter!, barplot, barplot!, hist, hist!, vlines!, save, figure, recolor!

const NAMED = Dict{Symbol,NTuple{4,Float64}}(
    :black => (0.0, 0.0, 0.0, 1.0), :white => (1.0, 1.0, 1.0, 1.0), :red => (0.85, 0.15, 0.15, 1.0),
    :green => (0.15, 0.6, 0.2, 1.0), :blue => (0.12, 0.35, 0.8, 1.0), :orange => (0.95, 0.55, 0.1, 1.0),
    :gray => (0.5, 0.5, 0.5, 1.0), :purple => (0.5, 0.2, 0.65, 1.0))
rgba(c::Symbol, i::Int) = get(NAMED, c, (0.0, 0.0, 0.0, 1.0))
rgba(c::NTuple{4,Float64}, i::Int) = c
rgba(c::Vector{NTuple{4,Float64}}, i::Int) = c[i]
npoints(p::AbstractMatrix) = size(p, 1)
pointx(p::AbstractMatrix, i::Int) = Float64(p[i, 1])
pointy(p::AbstractMatrix, i::Int) = Float64(p[i, 2])
npoints(p::AbstractVector{<:Tuple}) = length(p)
pointx(p::AbstractVector{<:Tuple}, i::Int) = Float64(p[i][1])
pointy(p::AbstractVector{<:Tuple}, i::Int) = Float64(p[i][2])
"A user's data: its points as a matrix or a vector of pairs."
points(d) = d

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
function circles!(c::Canvas, xs::Vector{Float64}, ys::Vector{Float64}, cols::Vector{NTuple{4,Float64}}, r::Float64)
    ctx = c.ctx
    for i in eachindex(xs)
        col = cols[i]
        Cairo.set_source_rgba(ctx, col[1], col[2], col[3], col[4])
        Cairo.new_sub_path(ctx)
        Cairo.arc(ctx, xs[i], ys[i], r, 0.0, 2pi)
        Cairo.fill(ctx)
    end
    return nothing
end
function text!(c::Canvas, x::Float64, y::Float64, s::String, size::Float64, halign::Symbol)
    ctx = c.ctx
    Cairo.set_source_rgba(ctx, 0.0, 0.0, 0.0, 1.0)
    Cairo.select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
    Cairo.set_font_size(ctx, size)
    ext = Cairo.text_extents(ctx, s)
    dx = halign === :center ? -ext[3] / 2 : halign === :right ? -ext[3] : 0.0
    Cairo.move_to(ctx, x + dx, y)
    Cairo.show_text(ctx, s)
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
mutable struct Axis
    plots::Vector{Any}
    title::String
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
function datalimits(p::PlotObj)
    a = p.attributes
    pos = points(a[:data])
    if p.kind === :bars
        w = a[:width]::Float64
        xmin, xmax, ymin, ymax = limits(pos)
        return (xmin - w / 2, xmax + w / 2, min(ymin, 0.0), max(ymax, 0.0))
    elseif p.kind === :vlines
        xmin, xmax, _, _ = limits(pos)
        return (xmin, xmax, Inf, -Inf)
    end
    return limits(pos)
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
function draw!(p::PlotObj, c::Canvas, t::Transform2D)
    a = p.attributes
    pos = points(a[:data])
    col = a[:color]
    if p.kind === :lines
        xs, ys = pixels(pos, t)
        polyline!(c, xs, ys, rgba(col, 1), a[:linewidth]::Float64)
    elseif p.kind === :scatter
        xs, ys = pixels(pos, t)
        circles!(c, xs, ys, colors(col, length(xs)), (a[:markersize]::Float64) / 2)
    elseif p.kind === :bars
        drawbars(pos, c, t, col, a[:width]::Float64)
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
    if !isfinite(xmin)
        xmin, xmax, ymin, ymax = 0.0, 1.0, 0.0, 1.0
    end
    dx, dy = 0.05 * max(xmax - xmin, 1e-12), 0.05 * max(ymax - ymin, 1e-12)
    xmin -= dx; xmax += dx; ymin -= dy; ymax += dy
    l, r, top, b = 60.0, W - 20.0, 40.0, H - 40.0
    t = Transform2D((r - l) / (xmax - xmin), l - (r - l) / (xmax - xmin) * xmin,
                    -(b - top) / (ymax - ymin), b + (b - top) / (ymax - ymin) * ymin, top, b)
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
        draw!(p, c, t)
    end
    writepng(c, path)
    return nothing
end

# --- the interface, as TraitMakie's ------------------------------------------------------------

figure(; size = (600, 400), title = "") = Figure(Int(size[1]), Int(size[2]), Axis(Any[], String(title)))
_xy(x::AbstractVector, y::AbstractVector) = hcat(Vector{Float64}(x), Vector{Float64}(y))
_color(c::Symbol) = c
_color(c::NTuple{4,<:Real}) = NTuple{4,Float64}(c)
_color(c::NTuple{3,<:Real}) = (Float64(c[1]), Float64(c[2]), Float64(c[3]), 1.0)
_color(c) = c
_add!(fig, kind, data, color; kw...) = (push!(fig.axis.plots, PlotObj(kind, Dict{Symbol,Any}(:data => data, :color => _color(color), kw...))); fig)
lines!(fig::Figure, x::AbstractVector, y::AbstractVector; color = :blue, linewidth = 1.5) = _add!(fig, :lines, _xy(x, y), color; linewidth = Float64(linewidth))
lines!(fig::Figure, data; color = :blue, linewidth = 1.5) = _add!(fig, :lines, data, color; linewidth = Float64(linewidth))
scatter!(fig::Figure, x::AbstractVector, y::AbstractVector; color = :black, markersize = 6) = _add!(fig, :scatter, _xy(x, y), color; markersize = Float64(markersize))
scatter!(fig::Figure, data; color = :black, markersize = 6) = _add!(fig, :scatter, data, color; markersize = Float64(markersize))
_gap(x) = length(x) < 2 ? 1.0 : 0.8 * minimum(diff(sort(Vector{Float64}(x))))
barplot!(fig::Figure, x::AbstractVector, y::AbstractVector; color = :blue, width = nothing) =
    _add!(fig, :bars, _xy(x, y), color; width = Float64(something(width, _gap(x))))
function hist!(fig::Figure, x::AbstractVector; bins::Integer = 10, color = :blue)
    v = Vector{Float64}(x)
    lo, hi = extrema(v)
    w = hi > lo ? (hi - lo) / bins : 1.0
    counts = zeros(bins)
    for xi in v
        counts[clamp(floor(Int, (xi - lo) / w) + 1, 1, bins)] += 1
    end
    return barplot!(fig, [lo + (k - 0.5) * w for k in 1:bins], counts; color, width = w)
end
vlines!(fig::Figure, xs::AbstractVector; color = :black, linewidth = 1.5) = _add!(fig, :vlines, _xy(xs, zeros(length(xs))), color; linewidth = Float64(linewidth))
vlines!(fig::Figure, x::Real; kw...) = vlines!(fig, [x]; kw...)
lines(args...; title = "", size = (600, 400), kw...) = lines!(figure(; size, title), args...; kw...)
scatter(args...; title = "", size = (600, 400), kw...) = scatter!(figure(; size, title), args...; kw...)
barplot(args...; title = "", size = (600, 400), kw...) = barplot!(figure(; size, title), args...; kw...)
hist(args...; title = "", size = (600, 400), kw...) = hist!(figure(; size, title), args...; kw...)
recolor!(fig::Figure, k::Integer, color) = (fig.axis.plots[k].attributes[:color] = _color(color); fig)
save(path::AbstractString, fig::Figure) = (render_png(fig, String(path)); path)

@compile_workload begin
    xs = collect(range(0.0, 2pi; length = 50))
    f = lines(xs, sin.(xs); title = "workload")
    scatter!(f, xs, cos.(xs); color = [(0.2, 0.4, 0.8, 1.0) for _ in xs])
    scatter!(f, xs, sin.(xs); color = :red)
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

"""
    MakieCompatPlain

The control of X3 (E-219, slice 2): the same old recipe API as MakieCompat, upstream's `stairs.jl` included
unchanged, above PlainPlots, a library written as Makie is (plots as kinds with `Dict` attributes, drawing
behind function barriers). Plain Julia throughout; MakieCompat's text, with PlainPlots' plots as the leaves.
"""
module MakieCompatPlain
import PlainPlots
export stairs, stairs!, Stairs, Point2, Point2f, Point2d

struct Point2{T <: Real} <: AbstractVector{T}
    x::T
    y::T
end
Base.size(::Point2) = (2,)
Base.getindex(p::Point2, i::Int) = i == 1 ? p.x : i == 2 ? p.y : throw(BoundsError(p, i))
const Point2f = Point2{Float32}
const Point2d = Point2{Float64}

mutable struct Node
    f::Any
    inputs::Vector{Symbol}
    last::Vector{Any}
    value::Any
    valid::Bool
end
struct Child
    prim::PlainPlots.PlotObj
    pos::Any
    attrs::Dict{Symbol, Any}
end
mutable struct Plot{F, T}
    converted::T
    attributes::Dict{Symbol, Any}
    graph::Dict{Symbol, Node}
    children::Vector{Child}
end
struct NodeRef
    plot::Any
    name::Symbol
end
const _FIELDS = (:converted, :attributes, :graph, :children)
Base.getproperty(p::Plot, s::Symbol) = s in _FIELDS ? getfield(p, s) : NodeRef(p, s)
function Base.setproperty!(p::Plot, s::Symbol, v)
    s in _FIELDS && return setfield!(p, s, v)
    haskey(getfield(p, :attributes), s) || throw(ArgumentError("$(typeof(p)) has no attribute :$s"))
    getfield(p, :attributes)[s] = v
end
function resolve(p::Plot, s::Symbol)
    m = match(r"^converted_(\d+)$", String(s))
    m === nothing || return getfield(p, :converted)[parse(Int, m[1])]
    attrs = getfield(p, :attributes)
    haskey(attrs, s) && return attrs[s]
    n = get(getfield(p, :graph), s, nothing)
    n === nothing && throw(ArgumentError("$(typeof(p)) has no input or node :$s"))
    vals = Any[resolve(p, i) for i in n.inputs]
    if !(n.valid && length(vals) == length(n.last) && all(((a, b),) -> a === b, zip(vals, n.last)))
        n.value = n.f(vals...)
        n.last = vals
        n.valid = true
    end
    return n.value
end
resolve(r::NodeRef) = resolve(r.plot, r.name)
resolve(x) = x
Base.map!(f, p::Plot, inputs::Vector{Symbol}, output::Symbol) = (getfield(p, :graph)[output] = Node(f, inputs, Any[], nothing, false); p)
function plot! end
struct PointBased end
conversion_trait(::Type) = nothing
function documented_attributes end

macro recipe(name, block)
    fname = Symbol(lowercase(String(name)))
    fname! = Symbol(fname, "!")
    items = Any[]
    for ex in block.args
        ex isa LineNumberNode && continue
        ex isa String && continue
        if ex isa Expr && ex.head === :macrocall && ex.args[1] == GlobalRef(Core, Symbol("@doc"))
            ex = ex.args[end]
        end
        if ex isa Expr && ex.head === :(=)
            push!(items, :($(QuoteNode(ex.args[1])) => $(esc(ex.args[2]))))
        elseif ex isa Expr && ex.head === :...
            push!(items, Expr(:..., esc(ex.args[1])))
        else
            error("@recipe $name: an attribute is `name = default` or a splatted list of pairs, not `$ex`")
        end
    end
    return quote
        Base.@__doc__ function $(esc(fname)) end
        const $(esc(name)){T} = Plot{typeof($(esc(fname))), T}
        $(esc(:documented_attributes))(::Type{<:Plot{typeof($(esc(fname)))}}) = Pair{Symbol, Any}[$(items...)]
        $(esc(fname!))(fig, args...; kw...) = _create!(fig, $(esc(fname)), args...; kw...)
        $(esc(fname))(args...; kw...) = (fig = PlainPlots.figure(); $(esc(fname!))(fig, args...; kw...); fig)
    end
end
function lines end
const Lines{T} = Plot{typeof(lines), T}
documented_attributes(::Type{<:Plot{typeof(lines)}}) = Pair{Symbol, Any}[:color => :blue, :linewidth => 1.5]
shared_attributes(p::Plot, ::Type{<:Plot{F}}) where {F} =
    Dict{Symbol, Any}(k => NodeRef(p, k) for (k, _) in documented_attributes(Plot{F}) if haskey(getfield(p, :attributes), k))
function lines!(p::Plot, attrs::Dict{Symbol, Any}, pos)
    prim = PlainPlots.PlotObj(:lines, Dict{Symbol, Any}(:pos => NTuple{2, Float64}[], :color => PlainPlots._color(:blue), :linewidth => 1.5))
    push!(getfield(p, :children), Child(prim, pos, attrs))
    return prim
end
_pointbased(xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real}) = (Point2d[Point2d(x, y) for (x, y) in zip(xs, ys)],)
_pointbased(ps::AbstractVector{<:Point2}) = (Point2d[Point2d(p[1], p[2]) for p in ps],)
_convert(::PointBased, args...) = _pointbased(args...)
function _create!(fig, f, args...; kw...)
    P0 = Plot{typeof(f)}
    converted = _convert(conversion_trait(P0), args...)
    attrs = Dict{Symbol, Any}(documented_attributes(P0))
    for (k, v) in kw
        haskey(attrs, k) || throw(ArgumentError("$(nameof(f)) has no attribute :$k"))
        attrs[k] = v
    end
    p = Plot{typeof(f), typeof(converted)}(converted, attrs, Dict{Symbol, Node}(), Child[])
    plot!(p)
    PlainPlots.plot!(fig, p)
    return p
end
# the hand-over: PlainPlots draws a user's plot through its own `datalimits` and `draw!`
function refresh!(p::Plot)
    for c in getfield(p, :children)
        a = PlainPlots.attrs(c.prim)
        a[:pos] = NTuple{2, Float64}[(q[1], q[2]) for q in resolve(c.pos)]
        haskey(c.attrs, :color) && (a[:color] = PlainPlots._color(resolve(c.attrs[:color])))
        haskey(c.attrs, :linewidth) && (a[:linewidth] = Float64(resolve(c.attrs[:linewidth])))
    end
    return p
end
function PlainPlots.datalimits(p::Plot)
    refresh!(p)
    xmin, xmax, ymin, ymax = Inf, -Inf, Inf, -Inf
    for c in getfield(p, :children)
        a, b, cc, d = PlainPlots.datalimits(c.prim)
        xmin = min(xmin, a); xmax = max(xmax, b); ymin = min(ymin, cc); ymax = max(ymax, d)
    end
    return (xmin, xmax, ymin, ymax)
end
function PlainPlots.draw!(p::Plot, c::PlainPlots.Canvas, t::PlainPlots.Transform2D)
    refresh!(p)
    for ch in getfield(p, :children)
        PlainPlots.draw!(ch.prim, c, t)
    end
    return nothing
end

include("upstream/stairs.jl")

import PrecompileTools
PrecompileTools.@compile_workload begin
    path = tempname() * ".png"
    f = PlainPlots.figure()
    p = stairs!(f, collect(1.0:5.0), [1.0, 3.0, 2.0, 4.0, 3.0]; step = :post, color = :red)
    p.step = :center
    PlainPlots.save(path, f)
    rm(path; force = true)
end

end

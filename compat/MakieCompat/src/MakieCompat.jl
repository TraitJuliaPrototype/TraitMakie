"""
    MakieCompat

The old Makie recipe API above TraitMakie's trait core (the lean-core memo §1.2; X3, slice 1, E-219):
upstream's `stairs.jl` (Makie 0.24.16) is included unchanged. Plain code that uses the trait world.

- `Plot{F, T}`, upstream's plot type: the plotting function's type and the converted arguments' types,
  with attributes, a compute graph (ComputePipeline's author API: `map!`, nodes read as `p.name`) and
  children.
- `@recipe Name begin … end`: `Name{T} = Plot{typeof(name), T}`, the attribute defaults, `name` and `name!`.
- Leaves are core primitives: `lines!(p, attrs, node)` in an old `plot!` makes a `PlotCore.Lines` child,
  fed the node's value at each use (the bridge).
- The hand-over: `Plot{F, T}` implements TraitMakie's `Plot` trait as a family, so an axis keeps old plots
  beside the core's.
"""
module MakieCompat
using TraitWorld
import TraitMakie
const PC = TraitMakie.PlotCore
# the old API's names are the umbrella's (TraitMakie.OldAPI); this package, a joint owner, gives them their
# machinery (X3, slice 2)
import TraitMakie.OldAPI: Plot, plot!, documented_attributes, conversion_trait, shared_attributes, lines!, lines
export stairs, stairs!, Stairs, Point2, Point2f, Point2d

# --- points (upstream: GeometryBasics' `Point2`) -----------------------------------------------------

"A point in the plane, as GeometryBasics' `Point2{T}` reads: `p[1]`, `p[2]`, `Point2{T}(x, y)`."
struct Point2{T <: Real} <: AbstractVector{T}
    x::T
    y::T
end
Base.size(::Point2) = (2,)
Base.getindex(p::Point2, i::Int) = i == 1 ? p.x : i == 2 ? p.y : throw(BoundsError(p, i))
const Point2f = Point2{Float32}
const Point2d = Point2{Float64}

# a vector of points is data the core's plots read (the layer owns `Point2`)
@implement PC.Positions V where {V <: AbstractVector{<:Point2}} begin
    npoints(p) = length(p)
    pointx(p, i) = Float64(p[i][1])
    pointy(p, i) = Float64(p[i][2])
end

# --- plots, the compute graph, recipes -------------------------------------------------------------

"A node of a plot's compute graph: `f` of the inputs' values, kept until an input changes."
mutable struct Node
    f::Any
    inputs::Vector{Symbol}
    last::Vector{Any}
    value::Any
    valid::Bool
end
"An old-style child: a core primitive and where its inputs come from."
struct Child
    prim::PC.Lines
    pos::Any                        # a `NodeRef` or a value
    attrs::Dict{Symbol, Any}        # attribute => `NodeRef` or value
end

# `Plot{F, T}` is the umbrella's (`TraitMakie.OldAPI.Plot`): its graph holds `Node`s, its children `Child`s
"A node or an attribute of a plot, as `p.name` reads it inside a recipe."
struct NodeRef
    plot::Any
    name::Symbol
end

Base.getproperty(p::Plot, s::Symbol) = s in (:converted, :attributes, :graph, :children) ? getfield(p, s) : NodeRef(p, s)
function Base.setproperty!(p::Plot, s::Symbol, v)
    s in (:converted, :attributes, :graph, :children) && return setfield!(p, s, v)
    haskey(getfield(p, :attributes), s) || throw(ArgumentError("$(typeof(p)) has no attribute :$s"))
    getfield(p, :attributes)[s] = v
end

"The current value of input or node `s` of plot `p`."
function resolve(p::Plot, s::Symbol)
    m = match(r"^converted_(\d+)$", String(s))
    m === nothing || return getfield(p, :converted)[parse(Int, m[1])]
    attrs = getfield(p, :attributes)
    haskey(attrs, s) && return attrs[s]
    n = get(getfield(p, :graph), s, nothing)
    n === nothing && throw(ArgumentError("$(typeof(p)) has no input or node :$s"))
    n = n::Node
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

"ComputePipeline's `map!`: node `output` of plot `p` is `f` of the inputs' values."
Base.map!(f, p::Plot, inputs::Vector{Symbol}, output::Symbol) =
    (getfield(p, :graph)[output] = Node(f, inputs, Any[], nothing, false); p)

struct PointBased end
conversion_trait(::Type{<:Plot}) = nothing

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
        Base.@__doc__ function $(esc(fname)) end          # a docstring on `@recipe` documents the plotting function
        const $(esc(name)){T} = Plot{typeof($(esc(fname))), T}
        $(esc(:documented_attributes))(::Type{<:Plot{typeof($(esc(fname)))}}) = Pair{Symbol, Any}[$(items...)]
        $(esc(fname!))(fig, args...; kw...) = _create!(fig, $(esc(fname)), args...; kw...)
        $(esc(fname))(args...; kw...) = (fig = TraitMakie.figure(); $(esc(fname!))(fig, args...; kw...); fig)
    end
end

# `lines`, a primitive (the umbrella's function): its attributes, as TraitMakie's own `lines!` takes them
const Lines{T} = Plot{typeof(lines), T}
documented_attributes(::Type{<:Plot{typeof(lines)}}) = Pair{Symbol, Any}[:color => :blue, :linewidth => 1.5]

"A recipe's attributes that `Lines` also has, read from the recipe (they follow its changes)."
shared_attributes(p::Plot, ::Type{<:Plot{F}}) where {F} =
    Dict{Symbol, Any}(k => NodeRef(p, k) for (k, _) in documented_attributes(Plot{F}) if haskey(getfield(p, :attributes), k))

"A line child of an old-style plot: a core `Lines`, fed at each use."
function lines!(p::Plot, attrs::Dict{Symbol, Any}, pos)
    prim = PC.Lines(Dynamic{PC.Positions}(Point2d[]), TraitMakie._color(:blue), 1.5)
    push!(getfield(p, :children), Child(prim, pos, attrs))
    return prim
end

# the conversion of `PointBased` arguments (upstream's `convert_arguments` for `PointBased`, the cases used)
_pointbased(xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real}) = (Point2d[Point2d(x, y) for (x, y) in zip(xs, ys)],)
_pointbased(ps::AbstractVector{<:Point2}) = (Point2d[Point2d(p[1], p[2]) for p in ps],)
_pointbased(ps::AbstractVector{<:Tuple{Real, Real}}) = (Point2d[Point2d(p[1], p[2]) for p in ps],)
_convert(::PointBased, args...) = _pointbased(args...)

"Make an old-style plot of `f` and add it to the figure (the creation pipeline, the cases used)."
function _create!(fig, f, args...; kw...)
    P0 = Plot{typeof(f)}
    converted = _convert(conversion_trait(P0), args...)
    attrs = Dict{Symbol, Any}(documented_attributes(P0))
    for (k, v) in kw
        haskey(attrs, k) || throw(ArgumentError("$(nameof(f)) has no attribute :$k"))
        attrs[k] = v
    end
    p = Plot{typeof(f), typeof(converted)}(converted, attrs, Dict{Symbol, Any}(), Any[])
    plot!(p)
    TraitMakie.plot!(fig, p)
    return p
end

# --- the hand-over: an old-style plot is a core `Plot` ----------------------------------------------

"The bridge: each child primitive given its inputs' current values."
function refresh!(p::Plot)
    for c in getfield(p, :children)
        c = c::Child
        c.prim.pos = Dynamic{PC.Positions}(resolve(c.pos))
        haskey(c.attrs, :color) && (c.prim.color = TraitMakie._color(resolve(c.attrs[:color])))
        haskey(c.attrs, :linewidth) && (c.prim.linewidth = Float64(resolve(c.attrs[:linewidth])))
    end
    return p
end
function _limits(p::Plot)
    refresh!(p)
    xmin, xmax, ymin, ymax = Inf, -Inf, Inf, -Inf
    for c in getfield(p, :children)
        a, b, cc, d = PC.datalimits((c::Child).prim)
        xmin = min(xmin, a); xmax = max(xmax, b); ymin = min(ymin, cc); ymax = max(ymax, d)
    end
    return (xmin, xmax, ymin, ymax)
end
function _draw!(p::Plot, c::PC.Canvas, t::PC.Transform2D)
    refresh!(p)
    for ch in getfield(p, :children)
        PC.draw!((ch::Child).prim, c, t)
    end
    return nothing
end
@implement PC.Plot P where {P <: Plot} begin
    datalimits(p) = _limits(p)
    draw!(p, c, t) = _draw!(p, c, t)
    setcolor!(p, c) = (getfield(p, :attributes)[:color] = c; nothing)
end

include("upstream/stairs.jl")

# a precompile workload, as an old recipe package would have one: the old-style path into the package image
TraitWorld.@workload begin
    path = tempname() * ".png"
    f = TraitMakie.figure()
    p = stairs!(f, collect(1.0:5.0), [1.0, 3.0, 2.0, 4.0, 3.0]; step = :post, color = :red)
    p.step = :center
    TraitMakie.save(path, f)
    rm(path; force = true)
end

end

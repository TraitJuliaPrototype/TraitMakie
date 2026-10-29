"""
    MakieCompat

The old Makie recipe API above TraitMakie's trait core (the lean-core memo §1.2; X3, E-219, E-222, E-223, E-226):
upstream's `stairs.jl` and `band.jl` (Makie 0.24.16) are included unchanged. Plain code that uses the trait world.

- `Plot{F, T}`, upstream's plot type: the plotting function's type and the converted arguments' types,
  with the arguments as given, attributes, a compute graph (ComputePipeline's author API: `map!`, nodes read
  as `p.name`) and children: leaves, and old-style plots of other recipes.
- `Attributes`: a plot's attributes by reference (`Attributes(p)`), passed to a child plot, which follows them.
- `Observable`s as arguments and attributes: read at each use; a notification marks the plot stale.
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
import TraitMakie.OldAPI: Plot, plot!, documented_attributes, conversion_trait, shared_attributes, lines!, lines,
                          convert_arguments, mesh!, mesh, Attributes, heatmap, voxels
# Observables.jl's `Observable`, the ecosystem's type, re-exported: a user's value that changes, as an argument or an
# attribute (here, not in the umbrella, so that the umbrella's environments need no new dependency)
using Observables: Observable, on
export stairs, stairs!, Stairs, band, band!, Band, Point2, Point2f, Point2d, Attributes, Observable
"`band.jl` extends `Makie.plot!`: the old API's module, here this one."
const Makie = @__MODULE__

# --- points (upstream: GeometryBasics' `Point2`) -----------------------------------------------------

"A point in the plane, as GeometryBasics' `Point2{T}` reads: `p[1]`, `p[2]`, `Point2{T}(x, y)`."
struct Point2{T <: Real} <: AbstractVector{T}
    x::T
    y::T
end
Base.size(::Point2) = (2,)
Base.getindex(p::Point2, i::Int) = i == 1 ? p.x : i == 2 ? p.y : throw(BoundsError(p, i))
Point2{T}(v::Real) where {T} = Point2{T}(v, v)
Point2(v::Real) = Point2(v, v)
Point2(x::Real, y::Real) = Point2(promote(x, y)...)
Base.isnan(p::Point2) = isnan(p.x) || isnan(p.y)
Base.reverse(p::Point2) = Point2(p.y, p.x)
const Point2f = Point2{Float32}
const Point2d = Point2{Float64}
"GeometryBasics' `Point3`, as far as `band.jl` names it."
struct Point3{T <: Real} <: AbstractVector{T}
    x::T
    y::T
    z::T
end
Base.size(::Point3) = (3,)
Base.getindex(p::Point3, i::Int) = (p.x, p.y, p.z)[i]
Point3(v::Real) = Point3(v, v, v)
"GeometryBasics' triangle face, by the indices of its vertices."
struct GLTriangleFace
    a::Int
    b::Int
    c::Int
end
"IntervalSets' interval, as far as `band.jl` reads it."
struct Interval{T}
    left::T
    right::T
end
leftendpoint(i::Interval) = i.left
rightendpoint(i::Interval) = i.right
"The float type of the arguments' elements."
float_type(xs...) = float(promote_type(map(eltype, xs)...))
"A colour as given (TraitMakie translates it where a primitive takes it)."
to_color(c) = c
"Makie's shading switch; a 2D canvas has none."
const NoShading = :none
"Makie's `automatic`: a default chosen from other values."
struct Automatic end
const automatic = Automatic()
"Upstream's `AbstractPlot`: here every old-style plot is a `Plot{F, T}`."
const AbstractPlot = Plot
"The extrema of the finite values, `(NaN, NaN)` if there are none (upstream's `extrema_nan`)."
function extrema_nan(itr)
    lo = hi = NaN
    for v in itr
        isfinite(v) || continue
        lo, hi = isnan(lo) ? (v, v) : (min(lo, v), max(hi, v))
    end
    return (lo, hi)
end

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
"""
An old-style leaf: its kind (`:lines`, `:mesh`) and where its inputs come from. Its core primitives are made from
their current values at each use (a line split at `NaN`s; a mesh as one polygon per triangle).
"""
struct Child
    kind::Symbol
    pos::Any                        # a `NodeRef` or a value
    faces::Any                      # a mesh's `NodeRef` or vector of faces; `nothing` for lines
    attrs::Dict{Symbol, Any}        # attribute => `NodeRef` or value
end

# `Plot{F, T}` is the umbrella's (`TraitMakie.OldAPI.Plot`): its graph holds `Node`s, its children `Child`s (leaves)
# and `Plot`s (a recipe's children)
"""
A node, an attribute or an argument of a plot, as `p.name` reads it inside a recipe (`p[k]`: argument `k` as given).
`r[]` is its current value; `r[] = v` sets an attribute or an argument.
"""
struct NodeRef
    plot::Any
    name::Symbol
end

const _FIELDS = (:converted, :args, :graph, :children)
Base.getproperty(p::Plot, s::Symbol) =
    s in _FIELDS ? getfield(p, s) : s === :attributes ? Attributes(p) : NodeRef(p, s)
Base.setproperty!(p::Plot, s::Symbol, v) = s in _FIELDS ? setfield!(p, s, v) : (_set!(p, s, v); v)
Base.getindex(p::Plot, k::Int) = NodeRef(p, Symbol(:arg, k))
Base.setindex!(p::Plot, v, k::Int) = (_set!(p, Symbol(:arg, k), v); p)
Base.getindex(r::NodeRef) = resolve(r)
Base.setindex!(r::NodeRef, v) = (_set!(r.plot, r.name, v); r)
"The plot's attributes as upstream's `Attributes`, by reference: a child given them follows the plot's changes."
Attributes(p::Plot) = Attributes(Dict{Symbol, Any}(k => NodeRef(p, k) for k in keys(getfield(p, :attributes))))

_argindex(s::Symbol) = (m = match(r"^arg(\d+)$", String(s)); m === nothing ? 0 : parse(Int, m[1]))
"Set attribute or argument `s` of `p` (an `Observable` given is watched)."
function _set!(p::Plot, s::Symbol, v)
    k = _argindex(s)
    if k > 0
        getfield(p, :args)[k] = v
    else
        attrs = getfield(p, :attributes)
        haskey(attrs, s) || throw(ArgumentError("$(typeof(p)) has no attribute :$s; a derived node is set through its inputs"))
        attrs[s] = v
    end
    _watch!(p, v)
    return nothing
end
"""
An `Observable` given to a plot is read at each use. When it notifies, the plot's nodes are marked stale, so a value
changed in place and notified is followed too (a plain listener: no trait code in the notification).
"""
_watch!(p::Plot, o::Observable) = (on(_ -> invalidate!(p), o); nothing)
_watch!(::Plot, _) = nothing
"Mark the nodes of `p` and of its child plots stale."
function invalidate!(p::Plot)
    for n in values(getfield(p, :graph))
        n isa Node && (n.valid = false)
    end
    for c in getfield(p, :children)
        c isa Plot && invalidate!(c)
    end
    return nothing
end

"A recipe's argument names (`@recipe Band (lowerpoints, upperpoints)`): the converted arguments' other names."
argnames(::Type{<:Plot}) = ()
"The current value of input or node `s` of plot `p`."
function resolve(p::Plot, s::Symbol)
    m = match(r"^converted_(\d+)$", String(s))
    m === nothing || return converted(p)[parse(Int, m[1])]
    k = _argindex(s)
    k > 0 && return resolve(getfield(p, :args)[k])
    k = findfirst(==(s), argnames(typeof(p)))
    k === nothing || return converted(p)[k]
    attrs = getfield(p, :attributes)
    haskey(attrs, s) && return resolve(attrs[s])
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
resolve(o::Observable) = o[]
resolve(x) = x
"The converted arguments, converted again when an argument's value changed (the node `:converted`)."
function converted(p::Plot{F, T}) where {F, T}
    c = resolve(p, :converted)
    c isa T || throw(ArgumentError("the converted arguments of a $(nameof(F)) plot changed type from $T to $(typeof(c)); make a new plot"))
    setfield!(p, :converted, c)
    return c
end

"ComputePipeline's `map!`: node `output` of plot `p` is `f` of the inputs' values."
Base.map!(f, p::Plot, inputs::Vector{Symbol}, output::Symbol) =
    (getfield(p, :graph)[output] = Node(f, inputs, Any[], nothing, false); p)
Base.map!(f, p::Plot, input::Symbol, output::Symbol) = map!(f, p, [input], output)

struct PointBased end
conversion_trait(::Type{<:Plot}) = nothing
"The cascade's last step: the conversion trait's conversion; a recipe without one takes its arguments as they are."
convert_arguments(::Type{P}, args::Vararg{Any, N}) where {P <: Plot, N} = _convert(conversion_trait(P), args...)
_convert(::Nothing, args::Vararg{Any, N}) where {N} = args

"Makie's theme, as far as the recipes here inherit from it (`@inherit name`)."
const THEME = Dict{Symbol, Any}(:patchstrokecolor => :black, :patchstrokewidth => 0.0, :colormap => :viridis,
                                :patchcolor => (0.0, 0.0, 0.0, 0.6))
macro inherit(name)
    return :(THEME[$(QuoteNode(name))])
end

macro recipe(name, block)
    return _recipe(name, (), block)
end
macro recipe(name, args, block)
    names = args isa Symbol ? (args,) : Tuple(args.args)
    return _recipe(name, names, block)
end
function _recipe(name, names, block)
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
        $(esc(:argnames))(::Type{<:Plot{typeof($(esc(fname)))}}) = $(QuoteNode(names))
        # compiled per number of arguments; `Vararg` escaped, since Julia's lowering of a method with keywords misses a
        # qualified `Vararg` (experiments/x3/tools/macro-vararg-hygiene.jl)
        $(esc(fname!))(fig, args::$(esc(:Vararg)){Any, N}; kw...) where {N} = _create!(fig, $(esc(fname)), args...; kw...)
        $(esc(fname))(args...; kw...) = (fig = TraitMakie.figure(); $(esc(fname!))(fig, args...; kw...); fig)
    end
end

# `lines`, a primitive (the umbrella's function): its attributes, as TraitMakie's own `lines!` takes them
const Lines{T} = Plot{typeof(lines), T}
documented_attributes(::Type{<:Plot{typeof(lines)}}) = Pair{Symbol, Any}[:color => :blue, :linewidth => 1.5]

"A recipe's attributes that `Lines` also has, by reference (they follow the recipe's changes)."
shared_attributes(p::Plot, ::Type{<:Plot{F}}) where {F} =
    Attributes(Dict{Symbol, Any}(k => NodeRef(p, k) for (k, _) in documented_attributes(Plot{F}) if haskey(getfield(p, :attributes), k)))

"A line child of an old-style plot: core `Lines`, fed at each use; keywords as attributes (`linewidth = p.strokewidth`)."
function lines!(p::Plot, attrs::Attributes, pos; kw...)
    a = merge(attrs.attributes, Dict{Symbol, Any}(kw))
    c = Child(:lines, pos, nothing, a)
    push!(getfield(p, :children), c)
    return c
end
# `mesh`, a primitive (the umbrella's function), as far as `band.jl` uses it
const Mesh{T} = Plot{typeof(mesh), T}
documented_attributes(::Type{<:Plot{typeof(mesh)}}) = Pair{Symbol, Any}[:color => :black, :alpha => 1.0]
"A mesh child: its vertices and triangle faces, drawn as one core `Poly` per triangle."
function mesh!(p::Plot, attrs::Attributes, coords, faces; kw...)
    a = merge(attrs.attributes, Dict{Symbol, Any}(kw))
    c = Child(:mesh, coords, faces, a)
    push!(getfield(p, :children), c)
    return c
end

# the conversion of `PointBased` arguments (upstream's `convert_arguments` for `PointBased`, the cases used)
_pointbased(xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real}) = (Point2d[Point2d(x, y) for (x, y) in zip(xs, ys)],)
_pointbased(ps::AbstractVector{<:Point2}) = (Point2d[Point2d(p[1], p[2]) for p in ps],)
_pointbased(ps::AbstractVector{<:Tuple{Real, Real}}) = (Point2d[Point2d(p[1], p[2]) for p in ps],)
_convert(::PointBased, args::Vararg{Any, N}) where {N} = _pointbased(args...)

"""
Make an old-style plot of `f` (the creation pipeline, the cases used) and add it to `target`: a figure, or a parent
plot whose recipe calls `f!` (a recipe child). Arguments may be values, a parent's nodes or `Observable`s; leading
`Attributes` give attribute values (a parent passes its own, `Attributes(plot)`). The conversion is the cascade: the
recipe's own `convert_arguments` where it has one for the arguments, else its conversion trait's. Each attribute is
the keyword's, else the given `Attributes`', else the recipe's default.
"""
_create!(target, f::F, given::Attributes, args::Vararg{Any, N}; kw...) where {F, N} = _make!(target, f, given, args; kw...)
_create!(target, f::F, args::Vararg{Any, N}; kw...) where {F, N} = _make!(target, f, Attributes(), args; kw...)
function _make!(target, f::F, given::Attributes, args::Tuple; kw...) where {F}
    P0 = Plot{typeof(f)}
    vals = map(resolve, args)
    conv = convert_arguments(P0, vals...)
    attrs = Dict{Symbol, Any}(documented_attributes(P0))
    for (k, v) in given
        haskey(attrs, k) ? (attrs[k] = v) :
            target isa Plot || throw(ArgumentError("$(nameof(f)) has no attribute :$k"))   # a parent's other attributes stay
    end
    for (k, v) in kw
        haskey(attrs, k) || throw(ArgumentError("$(nameof(f)) has no attribute :$k"))
        attrs[k] = v
    end
    p = Plot{typeof(f), typeof(conv)}(conv, Any[args...], attrs, Dict{Symbol, Any}(), Any[])
    reconvert(xs::Vararg{Any, M}) where {M} = convert_arguments(P0, xs...)
    getfield(p, :graph)[:converted] = Node(reconvert, Symbol[Symbol(:arg, i) for i in eachindex(args)], Any[vals...], conv, true)
    foreach(a -> _watch!(p, a), args)
    foreach(v -> _watch!(p, v), values(attrs))
    plot!(p)
    _add!(target, p)
    return p
end
_add!(parent::Plot, p::Plot) = (push!(getfield(parent, :children), p); nothing)
_add!(fig, p::Plot) = (TraitMakie.plot!(fig, p); nothing)

# --- the hand-over: an old-style plot is a core `Plot` ----------------------------------------------

_attr(c::Child, k::Symbol, default) = haskey(c.attrs, k) ? resolve(c.attrs[k]) : default
"A line's points split at `NaN`s: the core draws each run as one `Lines`."
function _runs(ps)
    out = Vector{Point2d}[]; cur = Point2d[]
    for q in ps
        if isnan(q)
            isempty(cur) || push!(out, cur); cur = Point2d[]
        else
            push!(cur, Point2d(q[1], q[2]))
        end
    end
    isempty(cur) || push!(out, cur)
    return out
end
"The bridge: the core primitives of a plot's leaves, and of its child plots' leaves, made from their inputs' current values."
function prims!(out::Vector{Dynamic{PC.Plot}}, p::Plot)
    for c in getfield(p, :children)
        c isa Child && prims!(out, c)
        c isa Plot && prims!(out, c)
    end
    return out
end
function prims!(out::Vector{Dynamic{PC.Plot}}, c::Child)
    col = TraitMakie._color(_attr(c, :color, :black))
    if c.kind === :lines
        lw = Float64(_attr(c, :linewidth, 1.5))
        for run in _runs(resolve(c.pos))
            push!(out, Dynamic{PC.Plot}(PC.Lines(Dynamic{PC.Positions}(run), col, lw)))
        end
    else
        vs = resolve(c.pos)
        for f in resolve(c.faces)
            tri = Point2d[Point2d(vs[i][1], vs[i][2]) for i in (f.a, f.b, f.c)]
            any(isnan, tri) && continue
            push!(out, Dynamic{PC.Plot}(PC.Poly(Dynamic{PC.Positions}(tri), col)))
        end
    end
    return out
end
prims(p::Plot) = prims!(Dynamic{PC.Plot}[], p)
function _limits(p::Plot)
    xmin, xmax, ymin, ymax = Inf, -Inf, Inf, -Inf
    for q in prims(p)
        a, b, cc, d = PC.datalimits(q)
        xmin = min(xmin, a); xmax = max(xmax, b); ymin = min(ymin, cc); ymax = max(ymax, d)
    end
    return (xmin, xmax, ymin, ymax)
end
function _draw!(p::Plot, c::PC.Canvas, t::PC.Transform2D)
    for q in prims(p)
        PC.draw!(q, c, t)
    end
    return nothing
end
@implement PC.Plot P where {P <: Plot} begin
    datalimits(p) = _limits(p)
    draw!(p, c, t) = _draw!(p, c, t)
    setcolor!(p, c) = (getfield(p, :attributes)[:color] = c; nothing)
end

"Makie's examples of a recipe's attributes (`band.jl` defines one); not used here."
function attribute_examples end

# names the statistics group's file (`hist.jl`) uses whose machinery this layer does not have yet: `barplot.jl` is
# not included, and `heatmap`, `voxels` are names of the umbrella's without leaves here
function barplot end
function barplot! end
const BarPlot{T} = Plot{typeof(barplot), T}
const Heatmap{T} = Plot{typeof(heatmap), T}
const Voxels{T} = Plot{typeof(voxels), T}

include("upstream/stairs.jl")
include("upstream/band.jl")

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

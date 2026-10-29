"""
    MakieCompat

The old Makie recipe API above TraitMakie's trait core (the lean-core memo §1.2; X3, E-219, E-222, E-223, E-226; W-32's
R2, E-240): upstream's `stairs.jl` and `band.jl` (Makie 0.24.16) are included unchanged, and a third-party recipe
package (GraphMakie) runs with `using Makie` read as `using MakieCompat`. Plain code that uses the trait world.

- `Plot{F, T}`, upstream's plot type: the plotting function's type and the converted arguments' types, with the
  arguments as given, attributes, a compute graph (ComputePipeline's author API on `p.attributes`: `map!` with one or
  several outputs, `add_input!`, `add_constant!`, nodes read as `p.name` or `p[:name]`), children (leaves, and
  old-style plots of other recipes) and a parent.
- `Attributes`: a plot's attributes by reference (`Attributes(p)`), passed to a child plot, which follows them.
- `Observable`s as arguments and attributes: read at each use; a notification marks the plot stale.
- `@recipe Name begin … end` and `@recipe(Name, args...) do scene … end`: `Name{T} = Plot{typeof(name), T}`, the
  attribute defaults (the do-block form's from its theme function), `name` (a figure, an axis and the plot) and `name!`.
- Leaves are core primitives: `lines!`, `scatter!`, `linesegments!`, `text!`, `mesh!` in an old `plot!` make
  `PlotCore` children, fed the nodes' values at each use (the bridge); numbers as colours go through the colormap.
- The hand-over: `Plot{F, T}` implements TraitMakie's `Plot` trait as a family, so an axis keeps old plots
  beside the core's.
- Upstream's user API, re-exported from the umbrella (`Figure`, `Axis`, `lines!`, `scatter!`, `save`, …), with
  GeometryBasics' points and Observables' `Observable`, `on` and `lift`, as `using Makie` brings them.
"""
module MakieCompat
using TraitWorld
import TraitMakie
const PC = TraitMakie.PlotCore
# the old API's names are the umbrella's (TraitMakie.OldAPI); this package, a joint owner, gives them their
# machinery (X3, slice 2). The plotting functions are the user API's own (one function per name, as upstream's).
import TraitMakie.OldAPI: Plot, plot!, documented_attributes, conversion_trait, shared_attributes, convert_arguments,
                          mesh!, mesh, Attributes, heatmap, voxels, lines!, lines, scatter!, scatter, text!, text,
                          linesegments!, linesegments
# upstream's user API, as `using Makie` brings it: the umbrella's
import TraitMakie: Figure, Axis, save, hidedecorations!, limits!
# Observables.jl's `Observable`, the ecosystem's type, re-exported: a user's value that changes, as an argument or an
# attribute (here, not in the umbrella, so that the umbrella's environments need no new dependency)
using Observables: Observables, Observable, on, onany, to_value
# GeometryBasics' points and shapes, the ecosystem's types, as upstream Makie re-exports them
using GeometryBasics: GeometryBasics, Point, Point2, Point3, Point2f, Point2d, Point3f, Point3d, Vec, Vec2f, Vec3f,
                      Vec2d, Rect, Rect2f, Rect2d, Circle, Polygon, GLTriangleFace
export @recipe, Plot, plot!, Attributes, Lines, Scatter, LineSegments, Text, Billboard, Linestyle, default_theme,
       lines, lines!, scatter, scatter!, linesegments, linesegments!, text, text!, Figure, Axis, save,
       hidedecorations!, limits!, Observable, on, onany, lift, to_value,
       Point, Point2, Point3, Point2f, Point2d, Point3f, Point3d, Vec, Vec2f, Vec3f, Vec2d, Rect, Rect2f, Rect2d, Circle,
       stairs, stairs!, Stairs, band, band!, Band, Makie,
       MouseEvent, MouseEventTypes, pick                    # names without machinery (interactive backends)
"The old API's module, here this one: a recipe's `Makie.plot!`, `Makie.documented_attributes` (`band.jl`, GraphMakie)."
const Makie = @__MODULE__

# --- names upstream's recipe files use -----------------------------------------------------------

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
"Upstream's `AbstractPlot` and `ScenePlot`: here every old-style plot is a `Plot{F, T}`."
const AbstractPlot = Plot
const ScenePlot = Plot
"The extrema of the finite values, `(NaN, NaN)` if there are none (upstream's `extrema_nan`)."
function extrema_nan(itr)
    lo = hi = NaN
    for v in itr
        isfinite(v) || continue
        lo, hi = isnan(lo) ? (v, v) : (min(lo, v), max(hi, v))
    end
    return (lo, hi)
end
"A marker's rotation that follows the screen (upstream's `Billboard`); the core's markers are not rotated."
struct Billboard{T}
    rotation::T
end
Billboard() = Billboard(0.0f0)
"A dash pattern (upstream's `Linestyle`); the core draws solid lines."
struct Linestyle
    value::Vector{Float32}
end

# names a recipe package mentions for interactive backends, documentation and 3D: no machinery here (TraitMakie draws
# PNGs; it has no events, no picking, no documentation tooling and no 3D scenes)
"Upstream's mouse event (interactive backends); a type for signatures only."
struct MouseEvent end
"Upstream's mouse event kinds (interactive backends); none here."
baremodule MouseEventTypes end
function registration_setup! end
function process_interaction end
function pick end
function preferred_axis_type end
function fast_string_boundingboxes end
"Makie's documentation tooling (DocStringExtensions' abbreviations); unused here."
struct DocThemer end
const ATTRIBUTES = DocThemer()

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
An old-style leaf: its kind (`:lines`, `:scatter`, `:linesegments`, `:text`, `:mesh`) and where its inputs come from.
Its core primitives are made from their current values at each use (a line split at `NaN`s; a mesh as one polygon per
triangle).
"""
struct Child
    kind::Symbol
    pos::Any                        # a `NodeRef` or a value
    faces::Any                      # a mesh's `NodeRef` or vector of faces; `nothing` for the others
    attrs::Dict{Symbol, Any}        # attribute => `NodeRef` or value
end

# `Plot{F, T}` is the umbrella's (`TraitMakie.OldAPI.Plot`): its graph holds `Node`s, its children `Child`s (leaves)
# and `Plot`s (a recipe's children), its parent the plot whose recipe made it, or the `Scene` of a top-level plot
"""
A node, an attribute or an argument of a plot, as `p.name` and `p[:name]` read it inside a recipe (`p[k]`: argument `k`
as given). `r[]` is its current value; `r[] = v` sets an attribute or an argument. Upstream's `Computed`.
"""
struct NodeRef
    plot::Any
    name::Symbol
end
"ComputePipeline's `Computed`: a node read by reference."
const Computed = NodeRef
"""
A plot's compute graph as a recipe reads `plot.attributes` (ComputePipeline's `ComputeGraph`): its attributes, inputs
and nodes by name, `map!`, `add_input!`, `add_constant!`. Given to a child (`lines!(p, p.attributes, …)`), the child
takes those of its attributes the graph has, by reference.
"""
struct ComputeGraph
    plot::Plot
end
"""
The scene a top-level old-style plot is drawn in, as a recipe reads it (`parent_scene`): its viewport and its camera's
projection, set by the axis at each render (`project` maps a point to pixels, y up).
"""
struct Scene
    viewport::Observable{Any}
    camera::Any
end
struct Camera
    projectionview::Observable{Any}
end
Scene() = Scene(Observable{Any}(nothing), Camera(Observable{Any}(nothing)))

const _FIELDS = (:converted, :args, :graph, :children, :parent)
Base.getproperty(p::Plot, s::Symbol) =
    s in _FIELDS ? getfield(p, s) : s === :attributes ? ComputeGraph(p) : s === :plots ? getfield(p, :children) :
    NodeRef(p, s)
Base.setproperty!(p::Plot, s::Symbol, v) = s in _FIELDS ? setfield!(p, s, v) : (_set!(p, s, v); v)
Base.getindex(p::Plot, k::Int) = NodeRef(p, Symbol(:arg, k))
Base.setindex!(p::Plot, v, k::Int) = (_set!(p, Symbol(:arg, k), v); p)
Base.getindex(p::Plot, s::Symbol) = NodeRef(p, s)
Base.setindex!(p::Plot, v, s::Symbol) = (_set!(p, s, v); p)
Base.haskey(p::Plot, s::Symbol) =
    haskey(getfield(p, :attributes), s) || haskey(getfield(p, :graph), s) || s in argnames(typeof(p)) || _argindex(s) > 0
Base.getindex(r::NodeRef) = resolve(r)
Base.setindex!(r::NodeRef, v) = (_set!(r.plot, r.name, v); r)
Base.getproperty(g::ComputeGraph, s::Symbol) = NodeRef(getfield(g, :plot), s)
Base.getindex(g::ComputeGraph, s::Symbol) = NodeRef(getfield(g, :plot), s)
Base.setindex!(g::ComputeGraph, v, s::Symbol) = (_set!(getfield(g, :plot), s, v); g)
Base.haskey(g::ComputeGraph, s::Symbol) = haskey(getfield(g, :plot), s)
"The plot's attributes as upstream's `Attributes`, by reference: a child given them follows the plot's changes."
Attributes(p::Plot) = Attributes(Dict{Symbol, Any}(k => NodeRef(p, k) for k in keys(getfield(p, :attributes))))
"Attributes given to a child: `Attributes` as they are; a compute graph as references to its attributes and nodes."
_attrs(a::Attributes) = getfield(a, :attributes)
function _attrs(g::ComputeGraph)
    p = getfield(g, :plot)
    d = Dict{Symbol, Any}(k => NodeRef(p, k) for k in keys(getfield(p, :attributes)))
    for k in keys(getfield(p, :graph))
        k === :converted || (d[k] = NodeRef(p, k))
    end
    return d
end

_argindex(s::Symbol) = (m = match(r"^arg(\d+)$", String(s)); m === nothing ? 0 : parse(Int, m[1]))
"Set attribute, input or argument `s` of `p` (an `Observable` given is watched)."
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
"`map!` with several outputs: `f` returns a tuple, one value per output (a node for the tuple, one per output)."
function Base.map!(f, p::Plot, inputs::Vector{Symbol}, outputs::Vector{Symbol})
    whole = Symbol(join(outputs, "|"))
    map!(f, p, inputs, whole)
    for (k, o) in enumerate(outputs)
        map!(t -> t[k], p, [whole], o)
    end
    return p
end
Base.map!(f, p::Plot, input::Symbol, outputs::Vector{Symbol}) = map!(f, p, [input], outputs)
Base.map!(f, g::ComputeGraph, inputs, outputs) = (map!(f, getfield(g, :plot), inputs, outputs); g)
"ComputePipeline's `add_input!`: an input of the plot's graph, set like an attribute (an `Observable` given is followed)."
function add_input!(p::Plot, name::Symbol, value)
    getfield(p, :attributes)[name] = value
    _watch!(p, value)
    return p
end
add_input!(g::ComputeGraph, name::Symbol, value) = (add_input!(getfield(g, :plot), name, value); g)
"ComputePipeline's `add_constant!`: a node of the plot's graph with a value that does not change."
add_constant!(p::Plot, name::Symbol, value) =
    (getfield(p, :graph)[name] = Node(() -> value, Symbol[], Any[], value, true); p)
add_constant!(g::ComputeGraph, name::Symbol, value) = (add_constant!(getfield(g, :plot), name, value); g)

"The scene a plot is drawn in: its top-level plot's."
function parent_scene(p::Plot)
    q = getfield(p, :parent)
    while q isa Plot
        q = getfield(q, :parent)
    end
    return q
end
"A point in pixels of the scene's last render (y up); the point itself before the first render."
function project(sc::Scene, point)
    t = sc.camera.projectionview[]
    t isa PC.Transform2D || return Point2f(point[1], point[2])
    return Point2f(PC.px(t, PC.scaled(t.xscale, Float64(point[1]))), -PC.py(t, PC.scaled(t.yscale, Float64(point[2]))))
end

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

"""
A plot type's defaults as upstream's `default_theme(scene, P)` gives them: `Attributes` of plain values for a recipe
with documented attributes; a do-block recipe's theme function's `Attributes`, each value an `Observable`.
"""
default_theme(scene, P::Type{<:Plot}) = Attributes(Dict{Symbol, Any}(documented_attributes(P)))
"A theme's values as `Observable`s (upstream's `Attributes` hold them so)."
_observed(a::Attributes) =
    Attributes(Dict{Symbol, Any}(k => (v isa Observable || v isa NodeRef ? v : Observable{Any}(v)) for (k, v) in _attrs(a)))
_themepairs(a::Attributes) = Pair{Symbol, Any}[k => v for (k, v) in _attrs(a)]

"`@recipe Name begin … end` and `@recipe Name (arg1, arg2) begin … end`: attributes as `name = default`."
macro recipe(name::Symbol, block::Expr)
    return _recipe(name, (), block)
end
macro recipe(name::Symbol, args::Expr, block::Expr)
    return _recipe(name, Tuple(args.args), block)
end
macro recipe(name::Symbol, arg::Symbol, block::Expr)
    return _recipe(name, (arg,), block)
end
"`@recipe(Name, args...) do scene … end`: the theme function gives the attributes and their defaults."
macro recipe(theme::Expr, name::Symbol, args::Symbol...)
    M = @__MODULE__
    fname = Symbol(lowercase(String(name)))
    P = :($Plot{typeof($(esc(fname)))})
    defs = quote
        $M.default_theme(scene, ::Type{<:$P}) = $M._observed($(esc(theme))(scene))
        $M.documented_attributes(::Type{<:$P}) = $M._themepairs($(esc(theme))(nothing))
    end
    return Expr(:block, _recipe_functions(name, fname, args), defs)
end
function _recipe(name, names, block)
    M = @__MODULE__
    fname = Symbol(lowercase(String(name)))
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
    defs = :($M.documented_attributes(::Type{<:$Plot{typeof($(esc(fname)))}}) = Pair{Symbol, Any}[$(items...)])
    return Expr(:block, _recipe_functions(name, fname, names), defs)
end
"""
What both forms define, in the caller's module: the plotting functions and the plot type (exported, as upstream's macro
does); in this module: the argument names. The old API's functions are named by this module (`MakieCompat.f`), so a recipe defined
in another package extends them.
"""
function _recipe_functions(name, fname, names)
    M = @__MODULE__
    fname! = Symbol(fname, "!")
    return quote
        Base.@__doc__ function $(esc(fname)) end          # a docstring on `@recipe` documents the plotting function
        const $(esc(name)){T} = $Plot{typeof($(esc(fname))), T}
        $M.argnames(::Type{<:$Plot{typeof($(esc(fname)))}}) = $(QuoteNode(Tuple(names)))
        # compiled per number of arguments; `Vararg` escaped, since Julia's lowering of a method with keywords misses a
        # qualified `Vararg` (experiments/x3/tools/macro-vararg-hygiene.jl)
        $(esc(fname!))(target, args::$(esc(:Vararg)){Any, N}; kw...) where {N} = $M._create!(target, $(esc(fname)), args...; kw...)
        $(esc(fname))(args...; kw...) = $M._figureaxisplot($(esc(fname!)), args...; kw...)
        $(esc(Expr(:export, name, fname, fname!)))
    end
end

"Upstream's `FigureAxisPlot`: what `name(args...)` returns, a figure, its axis and the plot; `fig, ax, p = …`."
struct FigureAxisPlot
    figure::PC.Figure
    axis::PC.Axis
    plot::Plot
end
Base.iterate(f::FigureAxisPlot, i::Int = 1) = i > 3 ? nothing : (getfield(f, i), i + 1)
Base.show(io::IO, f::FigureAxisPlot) = print(io, "FigureAxisPlot(", nameof(typeof(f.plot).parameters[1].instance), ")")
save(path::AbstractString, f::FigureAxisPlot; kw...) = save(path, f.figure; kw...)
function _figureaxisplot(f!, args...; figure = (;), axis = (;), kw...)
    fig = Figure(; figure...)
    ax = Axis(fig[1, 1]; axis...)
    p = f!(ax, args...; kw...)
    return FigureAxisPlot(fig, ax, p)
end

# the primitives (the umbrella's functions): their attributes, as upstream's themes give them
const Lines{T} = Plot{typeof(lines), T}
documented_attributes(::Type{<:Plot{typeof(lines)}}) = Pair{Symbol, Any}[:color => :blue, :linewidth => 1.5,
    :linestyle => nothing, :colormap => :viridis, :colorrange => automatic, :visible => true]
const LineSegments{T} = Plot{typeof(linesegments), T}
documented_attributes(::Type{<:Plot{typeof(linesegments)}}) = Pair{Symbol, Any}[:color => :black, :linewidth => 1.5,
    :linestyle => nothing, :colormap => :viridis, :colorrange => automatic, :visible => true]
const Scatter{T} = Plot{typeof(scatter), T}
documented_attributes(::Type{<:Plot{typeof(scatter)}}) = Pair{Symbol, Any}[:color => :black, :colormap => :viridis,
    :colorrange => automatic, :marker => :circle, :markersize => 9, :strokecolor => :black, :strokewidth => 0,
    :rotation => Billboard(), :markerspace => :pixel, :visible => true]
const Text{T} = Plot{typeof(text), T}
documented_attributes(::Type{<:Plot{typeof(text)}}) = Pair{Symbol, Any}[:text => "", :color => :black, :fontsize => 14,
    :align => (:left, :bottom), :offset => (0.0, 0.0), :rotation => 0.0, :markerspace => :pixel, :visible => true]
# `mesh`, a primitive (the umbrella's function), as far as `band.jl` uses it
const Mesh{T} = Plot{typeof(mesh), T}
documented_attributes(::Type{<:Plot{typeof(mesh)}}) = Pair{Symbol, Any}[:color => :black, :alpha => 1.0]

"A recipe's attributes that another plot type also has, by reference (they follow the recipe's changes)."
shared_attributes(p::Plot, ::Type{<:Plot{F}}) where {F} =
    Attributes(Dict{Symbol, Any}(k => NodeRef(p, k) for (k, _) in documented_attributes(Plot{F}) if haskey(getfield(p, :attributes), k)))

"""
A leaf of an old-style plot (`lines!(p, attrs, pos; kw...)`, `scatter!(p, pos; kw...)`, …): a core primitive fed at each
use; keywords as attributes (`linewidth = p.strokewidth`), else the given attributes (a compute graph's by reference).
"""
function _leaf!(p::Plot, kind::Symbol, attrs, pos, faces = nothing; kw...)
    c = Child(kind, pos, faces, merge(_attrs(attrs), Dict{Symbol, Any}(kw)))
    push!(getfield(p, :children), c)
    return c
end
const _Given = Union{Attributes, ComputeGraph}
lines!(p::Plot, attrs::_Given, pos; kw...) = _leaf!(p, :lines, attrs, pos; kw...)
lines!(p::Plot, pos; kw...) = _leaf!(p, :lines, Attributes(), pos; kw...)
scatter!(p::Plot, attrs::_Given, pos; kw...) = _leaf!(p, :scatter, attrs, pos; kw...)
scatter!(p::Plot, pos; kw...) = _leaf!(p, :scatter, Attributes(), pos; kw...)
linesegments!(p::Plot, attrs::_Given, pos; kw...) = _leaf!(p, :linesegments, attrs, pos; kw...)
linesegments!(p::Plot, pos; kw...) = _leaf!(p, :linesegments, Attributes(), pos; kw...)
text!(p::Plot, attrs::_Given, pos; kw...) = _leaf!(p, :text, attrs, pos; kw...)
text!(p::Plot, pos; kw...) = _leaf!(p, :text, Attributes(), pos; kw...)
"A mesh child: its vertices and triangle faces, drawn as one core `Poly` per triangle."
mesh!(p::Plot, attrs::_Given, coords, faces; kw...) = _leaf!(p, :mesh, attrs, coords, faces; kw...)

# the conversion of `PointBased` arguments (upstream's `convert_arguments` for `PointBased`, the cases used)
_pointbased(xs::AbstractVector{<:Real}, ys::AbstractVector{<:Real}) = (Point2d[Point2d(x, y) for (x, y) in zip(xs, ys)],)
_pointbased(ps::AbstractVector{<:Point2}) = (Point2d[Point2d(p[1], p[2]) for p in ps],)
_pointbased(ps::AbstractVector{<:Tuple{Real, Real}}) = (Point2d[Point2d(p[1], p[2]) for p in ps],)
_convert(::PointBased, args::Vararg{Any, N}) where {N} = _pointbased(args...)

"""
Make an old-style plot of `f` (the creation pipeline, the cases used) and add it to `target`: an axis, a figure, or a
parent plot whose recipe calls `f!` (a recipe child). Arguments may be values, a parent's nodes or `Observable`s; leading
`Attributes` (or a compute graph) give attribute values (a parent passes its own, `Attributes(plot)`). The conversion is
the cascade: the recipe's own `convert_arguments` where it has one for the arguments, else its conversion trait's. Each
attribute is the keyword's, else the given attributes', else the recipe's default.
"""
_create!(target, f::F, given::Attributes, args::Vararg{Any, N}; kw...) where {F, N} = _make!(target, f, given, args; kw...)
_create!(target, f::F, given::ComputeGraph, args::Vararg{Any, N}; kw...) where {F, N} =
    _make!(target, f, Attributes(_attrs(given)), args; kw...)
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
    parent = target isa Plot ? target : Scene()
    p = Plot{typeof(f), typeof(conv)}(conv, Any[args...], attrs, Dict{Symbol, Any}(), Any[], parent)
    reconvert(xs::Vararg{Any, M}) where {M} = convert_arguments(P0, xs...)
    getfield(p, :graph)[:converted] = Node(reconvert, Symbol[Symbol(:arg, i) for i in eachindex(args)], Any[vals...], conv, true)
    foreach(a -> _watch!(p, a), args)
    foreach(v -> _watch!(p, v), values(attrs))
    plot!(p)
    _add!(target, p)
    return p
end
_add!(parent::Plot, p::Plot) = (push!(getfield(parent, :children), p); nothing)
_add!(target, p::Plot) = (TraitMakie.plot!(target, p); nothing)

# --- the hand-over: an old-style plot is a core `Plot` ----------------------------------------------

_attr(c::Child, k::Symbol, default) = haskey(c.attrs, k) ? resolve(c.attrs[k]) : default
_isauto(x) = x === automatic || x === nothing
_isnanpoint(q) = any(isnan, q)
"The index ranges of a line's runs between `NaN` points: the core draws each run as one `Lines`."
function _runs(ps)
    out = UnitRange{Int}[]
    start = 0
    for (i, q) in enumerate(ps)
        if _isnanpoint(q)
            start > 0 && push!(out, start:i-1)
            start = 0
        elseif start == 0
            start = i
        end
    end
    start > 0 && push!(out, start:length(ps))
    return out
end
_points(ps, r) = Point2d[Point2d(ps[i][1], ps[i][2]) for i in r]
"""
A leaf's colour for the points `idx` (`nothing`: all) as the core takes it: numbers through the leaf's colormap, its
range from all the leaf's numbers unless given (upstream's `colorrange = automatic`); a vector of colours sliced; any
other colour as TraitMakie translates it.
"""
function _leafcolor(c::Child, default, idx)
    col = _attr(c, :color, default)
    if col isa AbstractVector{<:Real} || col isa Real
        cr = _attr(c, :colorrange, automatic)
        vals = col isa Real ? Float64[col] : Vector{Float64}(col)
        range = TraitMakie._crange(vals, _isauto(cr) ? nothing : cr)
        cm = TraitMakie._colormap(_attr(c, :colormap, :viridis))
        col isa Real && return PC.rgba(PC.MappedColors(vals, cm, range...), 1)     # one number: one colour
        return PC.MappedColors(idx === nothing ? vals : vals[idx], cm, range...)
    elseif col isa AbstractVector && idx !== nothing
        return TraitMakie._color(col[idx])
    else
        return TraitMakie._color(col)
    end
end
_one(x::AbstractVector, i) = x[i]
_one(x, i) = x
"A marker as the core takes it: one of its named shapes (`:circle`, …; GeometryBasics' `Circle` is `:circle`)."
_leafmarker(m::Symbol) = TraitMakie._marker(m)
_leafmarker(m::AbstractVector{Symbol}) = TraitMakie._marker(m)
_leafmarker(::Type{<:Circle}) = TraitMakie._marker(:circle)
_leafmarker(m) = throw(ArgumentError("marker $(repr(m)): the core draws its named markers ($(join(sort!(collect(keys(PC.MARKERS))), ", "))) only"))
_leafalign(a::Tuple{Symbol, Symbol}) = a[1]
_leafalign(a::Symbol) = a
_leafalign(a::AbstractVector) = _leafalign(first(a))
"The bridge: the core primitives of a plot's leaves, and of its child plots' leaves, made from their inputs' current values."
function prims!(out::Vector{Dynamic{PC.Plot}}, p::Plot)
    for c in getfield(p, :children)
        c isa Child && prims!(out, c)
        c isa Plot && prims!(out, c)
    end
    return out
end
function prims!(out::Vector{Dynamic{PC.Plot}}, c::Child)
    _attr(c, :visible, true) === false && return out
    if c.kind === :lines
        lw = _attr(c, :linewidth, 1.5)
        ls = _attr(c, :linestyle, nothing)
        (ls === nothing || ls === :solid) || throw(ArgumentError("linestyle $(repr(ls)): the core draws solid lines only"))
        ps = resolve(c.pos)
        for r in _runs(ps)
            push!(out, Dynamic{PC.Plot}(PC.Lines(Dynamic{PC.Positions}(_points(ps, r)), _leafcolor(c, :black, r),
                                                 Float64(_one(lw, first(r))))))
        end
    elseif c.kind === :linesegments
        lw = _attr(c, :linewidth, 1.5)
        ps = resolve(c.pos)
        for k in 1:2:length(ps)-1
            r = k:k+1
            any(i -> _isnanpoint(ps[i]), r) && continue
            push!(out, Dynamic{PC.Plot}(PC.Lines(Dynamic{PC.Positions}(_points(ps, r)), _leafcolor(c, :black, r),
                                                 Float64(_one(lw, k)))))
        end
    elseif c.kind === :scatter
        ps = resolve(c.pos)
        keep = [i for i in eachindex(ps) if !_isnanpoint(ps[i])]
        isempty(keep) && return out
        ms = _attr(c, :markersize, 9)
        push!(out, Dynamic{PC.Plot}(PC.Scatter(Dynamic{PC.Positions}(_points(ps, keep)), _leafcolor(c, :black, keep),
                                               Float64(_one(ms, first(keep))), _leafmarker(_attr(c, :marker, :circle)))))
    elseif c.kind === :text
        ps = resolve(c.pos)
        ps isa AbstractVector{<:Real} && (ps = [ps])                     # one position
        txt = _attr(c, :text, "")
        texts = txt isa AbstractVector ? String[string(s) for s in txt] : fill(string(txt), length(ps))
        push!(out, Dynamic{PC.Plot}(PC.Labels(Dynamic{PC.Positions}(_points(ps, eachindex(ps))), texts,
                                              _leafcolor(c, :black, nothing), Float64(_one(_attr(c, :fontsize, 14), 1)),
                                              TraitMakie._align(_leafalign(_attr(c, :align, (:left, :bottom)))))))
    else
        col = TraitMakie._color(_attr(c, :color, :black))
        vs = resolve(c.pos)
        for f in resolve(c.faces)
            tri = Point2d[Point2d(vs[i][1], vs[i][2]) for i in f]           # a face's indices index the vertices
            any(_isnanpoint, tri) && continue
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
    sc = parent_scene(p)
    if sc isa Scene && sc.camera.projectionview[] !== t          # the scene's projection, for recipes that read it
        sc.viewport[] = (c.width, c.height)
        sc.camera.projectionview[] = t
    end
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

# --- Observables in the user API ----------------------------------------------------------------------

"Upstream's `lift(f, obs, args...)`: an `Observable` of `f` of the arguments' values, updated when one of them changes."
lift(f, o::Observable, args...) = map(f, o, args...)
"""
An `Observable` of points or of numbers mirrored into the core's `Live` (`TraitMakie.Live`): the live value follows each
notification (a plain listener), and a plot made from it reads the current value at each render.
"""
function _live(o::Observable, conv)
    lv = TraitMakie.Live(conv(o[]))
    on(v -> (lv[] = conv(v)), o)
    return lv
end
_matrix(ps::AbstractVector) = Float64[ps[i][j] for i in eachindex(ps), j in 1:2]
_floats(v::AbstractVector{<:Real}) = Vector{Float64}(v)
lines!(ax::PC.Axis, o::Observable; kw...) = lines!(ax, _live(o, _matrix); kw...)
scatter!(ax::PC.Axis, o::Observable; kw...) = scatter!(ax, _live(o, _matrix); kw...)
"An `Observable` of numbers as a colour: mapped through the colormap; the range from its first value unless given."
TraitMakie._color(o::Observable, colormap, colorrange) =
    PC.MappedColors(_live(o, _floats), TraitMakie._colormap(colormap), TraitMakie._crange(o[], colorrange)...)
TraitMakie._color(o::Observable) = TraitMakie._color(o, :viridis, nothing)

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

# a precompile workload, as an old recipe package would have one: the old-style path into the package image, the leaves,
# and the user API with an `Observable`
TraitWorld.@workload begin
    path = tempname() * ".png"
    f = TraitMakie.figure()
    p = stairs!(f, collect(1.0:5.0), [1.0, 3.0, 2.0, 4.0, 3.0]; step = :post, color = :red)
    p.step = :center
    TraitMakie.save(path, f)
    fig = Figure(size = (400, 300))
    ax = Axis(fig[1, 1])
    q = stairs!(ax, collect(1.0:5.0), [1.0, 3.0, 2.0, 4.0, 3.0])
    scatter!(q, Point2f[(1, 1), (2, 3), (3, 2)]; color = [0.0, 0.5, 1.0], colormap = :balance, markersize = 14)
    lines!(q, q.attributes, Point2f[(1, 1), (2, 3), (NaN, NaN), (3, 2), (4, 4)]; color = [0.0, 0.5, 1.0, 1.0, 0.2])
    hidedecorations!(ax)
    obs = Observable(Point2f[(0, 0), (1, 1)])
    a2 = Axis(fig[1, 2])
    lines!(a2, obs)
    limits!(a2, 0, 2, 0, 2)
    save(path, fig)
    obs[] = Point2f[(0, 1), (2, 0)]
    save(path, fig)
    rm(path; force = true)
end

end

# Row 8: errors at the entry or the conformance, naming the bound. Three cases:
#   1. bad data: a value that conforms to no data trait, passed where `Positions` is bound;
#   2. a wrong colour result: a user's colour whose `rgba` returns three numbers, not four;
#   3. an undeclared operation in a recipe: a user's recipe, written as trait-world code, that
#      calls `length` on its positions (not an operation of `Positions`).
# Each: where it is caught, the message's first line, its lines and frames (as TDE's scripts/errors.jl).
#
#     JULIA_LOAD_PATH="scripts/env:@stdlib" julia --startup-file=no scripts/errors.jl
using TraitMakie, TraitWorld
function report(name, thunk)
    msg = try
        thunk()
        "no error"
    catch e
        sprint((io, e, bt) -> showerror(IOContext(io, :limit => false), e, bt), e, catch_backtrace())
    end
    lines = split(msg, '\n')
    frames = count(l -> occursin(r"^\s*\[\d+\]", l), lines)
    println(rpad(name, 40), " lines ", length(lines), ", frames ", frames, ", longest line ", maximum(length, lines))
    println("    ", first(lines)[1:min(end, 220)])
    get(ENV, "SHOW", "0") == "1" && println(msg, "\n")
end
f = TraitMakie.lines(collect(1.0:10.0), collect(1.0:10.0))
report("1. bad data", () -> TraitMakie.lines!(f, "not data"))
struct RGB3; r::Float64; g::Float64; b::Float64; end
TraitMakie.rgba(c::RGB3, i::Int) = (c.r, c.g, c.b)
report("2. a wrong colour result", () -> @eval @implement ColorSpec RGB3)
# at the prompt the definition check warns (at a package's build it is an error); the call raises
io = IOBuffer()
using Logging
with_logger(SimpleLogger(io)) do
    @eval @trait_module module MyRecipes
        using TraitWorld, TraitMakie
        using TraitMakie.PlotCore: Canvas, Transform2D
        export Dots
        mutable struct Dots; pos::Positions; end
        TraitMakie.PlotCore.datalimits(d::Dots) = (0.0, 1.0, 0.0, 1.0)
        count_points(p::Positions) = length(p)                # `length` is no operation of Positions
        TraitMakie.PlotCore.draw!(d::Dots, c::Canvas, t::Transform2D) = (count_points(d.pos); nothing)
        TraitMakie.PlotCore.setcolor!(d::Dots, c::Dynamic{ColorSpec}) = nothing
        @implement Plot Dots
    end
end
w = split(String(take!(io)), '\n')
println(rpad("3. an undeclared operation in a recipe", 40), " at its definition, a warning of ", count(!isempty, w), " lines:")
println("    ", join(filter(l -> occursin("length", l), w), " "))
g = TraitMakie.figure()
push!(g.axis.plots, Dynamic{TraitMakie.Plot}(MyRecipes.Dots(Dynamic{Positions}([1.0 2.0; 3.0 4.0]))))
report("   and at the first call", () -> TraitMakie.save(tempname() * ".png", g))

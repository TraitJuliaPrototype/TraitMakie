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
# the definition check refuses the method where it is defined (in a script as at a package's build; at the
# prompt it warns): the module's evaluation raises
report("3. an undeclared operation in a recipe", () -> @eval module MyRecipes
        using TraitWorld, TraitMakie
        @trait_module
        using TraitMakie.PlotCore: Canvas, Transform2D
        export Dots
        mutable struct Dots; pos::Positions; end
        TraitMakie.PlotCore.datalimits(d::Dots) = (0.0, 1.0, 0.0, 1.0)
        count_points(p::Positions) = length(p)                # `length` is no operation of Positions
        TraitMakie.PlotCore.draw!(d::Dots, c::Canvas, t::Transform2D) = (count_points(d.pos); nothing)
        TraitMakie.PlotCore.setcolor!(d::Dots, c::ColorSpec) = nothing
        @implement Plot Dots
    end)

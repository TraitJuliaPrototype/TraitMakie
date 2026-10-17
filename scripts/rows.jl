# Rows 1, 4 and 6 of the README in one fresh process, with big loads before, after or not at all.
#
#     JULIA_LOAD_PATH="<env with TraitMakie>:<env with CSV, DataFrames, CairoMakie>:@stdlib" \
#         julia --startup-file=no scripts/rows.jl none|before|after
#
# "after": CSV, DataFrames and CairoMakie load after the first PNG, before rows 4 and 6.
# Each line is one first call: "row <n> <what> <ms>".
const LOADS = ARGS[1]
load_big() = (t = @elapsed(@eval Main using CSV, DataFrames, CairoMakie); println("loads ", round(t; digits = 2), " s"))
LOADS == "before" && load_big()
row(n, what, t) = println("row ", n, " ", what, " ", round(1000t; digits = 1), " ms")
row(1, "using TraitMakie", @elapsed @eval using TraitMakie, TraitWorld)
const TM = TraitMakie                     # qualified: CairoMakie exports lines, scatter!, save too
const OUT = mktempdir()
xs = collect(range(0.0, 2pi; length = 100))
row(1, "first PNG: lines, scatter, save", @elapsed (f = TM.lines(xs, sin.(xs); title = "t"); TM.scatter!(f, xs, cos.(xs); color = :red); TM.save(joinpath(OUT, "a.png"), f)))
LOADS == "after" && load_big()

@eval struct Trajectory; name::String; pts::Vector{NTuple{2,Float64}}; end
row(4, "a new data type: @implement (forwarding)", @elapsed @eval @implement TM.Positions Trajectory)
tr = Trajectory("w", [(Float64(i), Float64(i)^2) for i in 1:20])
row(4, "a new data type: first PNG", @elapsed TM.save(joinpath(OUT, "b.png"), TM.lines(tr)))
@eval struct Gradient; from::NTuple{4,Float64}; to::NTuple{4,Float64}; n::Int; end
@eval TraitMakie.rgba(g::Gradient, i::Int) = (t = (i - 1) / max(g.n - 1, 1); g.from .+ t .* (g.to .- g.from))
row(4, "a new colour type: @implement", @elapsed @eval @implement TM.ColorSpec Gradient)
g = Gradient((1.0, 0.0, 0.0, 1.0), (0.0, 0.0, 1.0, 1.0), length(xs))
f2 = TM.lines(tr; color = (0.1, 0.5, 0.2))
row(4, "a new colour type: first PNG", @elapsed (TM.scatter!(f2, xs, sin.(xs); color = g); TM.save(joinpath(OUT, "c.png"), f2)))

row(6, "render", @elapsed TM.save(joinpath(OUT, "d.png"), f2))
row(6, "recolor to a vector, render", @elapsed (TM.recolor!(f2, 2, [(0.1, 0.2, 0.3, 1.0) for _ in xs]); TM.save(joinpath(OUT, "e.png"), f2)))
row(6, "recolor to :purple, render", @elapsed (TM.recolor!(f2, 2, :purple); TM.save(joinpath(OUT, "f.png"), f2)))
row(6, "recolor plot 1 to a Gradient, render", @elapsed (TM.recolor!(f2, 1, Gradient((0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), 20)); TM.save(joinpath(OUT, "g.png"), f2)))

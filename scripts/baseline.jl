# TraitMakie against PlainPlots (baselines/PlainPlots: the same library without traits), one fresh
# process per library and load order: first PNG; a new data type and a new colour type (row 4);
# a 10⁵-point line updated in place and drawn 100 times, and 50 plots drawn (row 9).
#
#     JULIA_LOAD_PATH="scripts/env:../experiments/interfaces/env:@stdlib" julia --startup-file=no scripts/baseline.jl TraitMakie|PlainPlots none|before
const LIB, LOADS = Symbol(ARGS[1]), ARGS[2]
LOADS == "before" && @eval using CSV, DataFrames, CairoMakie
t0 = time()
@eval using $LIB, TraitWorld
const P = getfield(Main, LIB)
row(what, t) = println(rpad(string(LIB), 12), rpad(what, 46), round(1000t; digits = 1), " ms")
row("using", time() - t0)
const OUT = mktempdir()
xs = collect(range(0.0, 2pi; length = 100))
row("first PNG: lines, scatter, save", @elapsed (f = P.lines(xs, sin.(xs); title = "t"); P.scatter!(f, xs, cos.(xs); color = :red); P.save(joinpath(OUT, "a.png"), f)))

@eval struct Trajectory; name::String; pts::Vector{NTuple{2,Float64}}; end
@eval struct Gradient; from::NTuple{4,Float64}; to::NTuple{4,Float64}; n::Int; end
if LIB === :TraitMakie
    row("a new data type: conformance", @elapsed @eval @implement TraitMakie.Positions Trajectory by pts)
    @eval TraitMakie.rgba(g::Gradient, i::Int) = (t = (i - 1) / max(g.n - 1, 1); g.from .+ t .* (g.to .- g.from))
    row("a new colour type: conformance", @elapsed @eval @implement TraitMakie.ColorSpec Gradient)
else
    row("a new data type: method", @elapsed @eval PlainPlots.points(d::Trajectory) = d.pts)
    row("a new colour type: method", @elapsed @eval PlainPlots.rgba(g::Gradient, i::Int) = (t = (i - 1) / max(g.n - 1, 1); g.from .+ t .* (g.to .- g.from)))
end
tr = Trajectory("w", [(Float64(i), Float64(i)^2) for i in 1:20])
row("a new data type: first PNG", @elapsed P.save(joinpath(OUT, "b.png"), P.lines(tr)))
row("a new colour type: first PNG", @elapsed P.save(joinpath(OUT, "c.png"), P.scatter(xs, sin.(xs); color = Gradient((1.0, 0, 0, 1.0), (0, 0, 1.0, 1.0), length(xs)))))

# row 9: a 10⁵-point line, its data changed in place and the figure drawn 100 times
N = 10^5
xN = collect(range(0.0, 100.0; length = N)); yN = sin.(xN)
fN = P.lines(xN, yN; size = (1200, 800))
P.save(joinpath(OUT, "n.png"), fN)
tn = @elapsed for k in 1:100
    if LIB === :TraitMakie
        P.recolor!(fN, 1, :blue)                     # the same work for both: the figure drawn again
    else
        P.recolor!(fN, 1, :blue)
    end
    P.save(joinpath(OUT, "n.png"), fN)
end
row("10⁵-point line drawn 100 times (per drawing)", tn / 100)
f50 = P.figure(; size = (1200, 800))
for k in 1:50
    P.lines!(f50, xs, sin.(xs .+ k / 10); color = :gray)
end
P.save(joinpath(OUT, "m.png"), f50)
row("50 plots drawn (per drawing)", @elapsed(for k in 1:20; P.save(joinpath(OUT, "m.png"), f50); end) / 20)

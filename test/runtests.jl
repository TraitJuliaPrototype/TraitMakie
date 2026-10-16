using Test, TraitMakie, TraitWorld

struct Trajectory; name::String; pts::Vector{NTuple{2,Float64}}; end
@implement Positions Trajectory                     # forwards to its one conforming field

struct Gradient; from::NTuple{4,Float64}; to::NTuple{4,Float64}; n::Int; end
TraitMakie.rgba(g::Gradient, i::Int) = (t = (i - 1) / max(g.n - 1, 1); g.from .+ t .* (g.to .- g.from))
@implement ColorSpec Gradient                       # a colour of the user's own, per point

@testset "TraitMakie: PlotCore with lines and scatter" begin
    xs = collect(range(0.0, 2pi; length = 100))
    f = lines(xs, sin.(xs); title = "t")
    scatter!(f, xs, cos.(xs); color = :red)
    @test length(f.axis.plots) == 2
    p = save(tempname() * ".png", f)
    @test isfile(p) && filesize(p) > 1000
    # the user's data type and colour: one-line conformances
    f2 = lines(Trajectory("w", [(Float64(i), Float64(i)^2) for i in 1:20]); color = (0.1, 0.5, 0.2))
    scatter!(f2, xs, sin.(xs); color = Gradient((1.0, 0.0, 0.0, 1.0), (0.0, 0.0, 1.0, 1.0), length(xs)))
    p2 = save(tempname() * ".png", f2)
    @test isfile(p2) && filesize(p2) > 1000
    # limits through the dynamic values
    @test TraitMakie.PlotCore.datalimits(f2.axis.plots[1]) == (1.0, 20.0, 1.0, 400.0)
    # a value that does not conform is refused at the bound, naming it
    @test_throws Exception lines!(f, "not data")
end

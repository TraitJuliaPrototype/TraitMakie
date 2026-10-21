using Test, TraitMakie, TraitWorld
import PlainPlots
const PC = TraitMakie.PlotCore
const Cairo = PC.Cairo

struct Trajectory; name::String; pts::Vector{NTuple{2,Float64}}; end
@implement Positions Trajectory by pts              # forwards to its field `pts`

struct Gradient; from::NTuple{4,Float64}; to::NTuple{4,Float64}; n::Int; end
TraitMakie.rgba(g::Gradient, i::Int) = (t = (i - 1) / max(g.n - 1, 1); g.from .+ t .* (g.to .- g.from))
@implement ColorSpec Gradient                       # a colour of the user's own, per point

struct Star; n::Int; end                            # a marker of the user's own
TraitMakie.outline(s::Star, i::Int) = [(k % 2 == 0 ? 1.2 : 0.5) .* (sin(pi * k / s.n), -cos(pi * k / s.n)) for k in 0:2s.n-1]
@implement MarkerShape Star

mutable struct Sensor; label::String; readings::Vector{NTuple{2,Float64}}; end
@implement Positions Sensor by readings             # a live source of the user's own: read at each render

"A user's recipe with children: a centre line and a band around it, made of the library's recipes."
mutable struct Ribbon
    center::Lines
    band::Band
end
function Ribbon(x::Vector{Float64}, y::Vector{Float64}, halfwidth::Float64; color = :blue)
    m = hcat(x, y)
    band = Band(hcat(x, y .- halfwidth), hcat(x, y .+ halfwidth), (0.5, 0.5, 0.5, 0.3), Poly(zeros(0, 2), :gray))
    return Ribbon(Lines(m, color, 2.0), band)       # fields of a trait's name take plain values (converted at X)
end
function TraitMakie.datalimits(r::Ribbon)
    a, b = TraitMakie.datalimits(r.center), TraitMakie.datalimits(r.band)
    return (min(a[1], b[1]), max(a[2], b[2]), min(a[3], b[3]), max(a[4], b[4]))
end
TraitMakie.PlotCore.draw!(r::Ribbon, c::PC.Canvas, t::PC.Transform2D) = (PC.draw!(r.band, c, t); PC.draw!(r.center, c, t))
TraitMakie.PlotCore.setcolor!(r::Ribbon, c::Kept{ColorSpec}) = (r.center.color = c; nothing)
@implement Plot Ribbon

"The pixels of a PNG file (ARGB, one UInt32 each), as a width × height matrix."
function pngpixels(path)
    s = Cairo.read_from_png(path)
    w, h = Int(s.width), Int(s.height)
    stride = ccall((:cairo_image_surface_get_stride, Cairo.libcairo), Int32, (Ptr{Nothing},), s.ptr)
    p = ccall((:cairo_image_surface_get_data, Cairo.libcairo), Ptr{UInt32}, (Ptr{Nothing},), s.ptr)
    return copy(unsafe_wrap(Array, p, (Int(stride) ÷ 4, h))[1:w, :])
end
"The fraction of pixels that differ between two PNG files (1.0 if their sizes differ)."
pngdiff(a, b) = (A = pngpixels(a); B = pngpixels(b); size(A) == size(B) ? count(A .!= B) / length(A) : 1.0)
datalim(f, k) = TraitMakie.datalimits(f.axis.plots[k])
const OUT = mktempdir()
png(name) = joinpath(OUT, name * ".png")

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
    @test datalim(f2, 1) == (1.0, 20.0, 1.0, 400.0)
    # the colour changes shape on an existing plot (row 6): a symbol, a vector, the user's type, a symbol
    recolor!(f2, 2, [(0.1, 0.2, 0.3, 1.0) for _ in xs])
    recolor!(f2, 2, :purple)
    recolor!(f2, 1, Gradient((0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), 20))
    @test isfile(save(tempname() * ".png", f2))
    # a value that does not conform is refused at the bound, naming it
    @test_throws Exception lines!(f, "not data")
end

@testset "TraitMakie: bars, histograms, vertical lines" begin
    x = [0.1i for i in 1:200]
    h = hist(x; bins = 24, title = "h", size = (1200, 800))
    vlines!(h, sum(x) / length(x); color = :red)
    l = datalim(h, 1)
    @test l[3] == 0.0 && l[1] ≈ 0.1 && l[2] ≈ 20.0
    @test datalim(h, 2)[3] == Inf
    p = save(tempname() * ".png", h)
    @test isfile(p) && filesize(p) > 1000
    @test isfile(save(tempname() * ".png", barplot([1, 2, 3], [3.0, 1.0, 2.0]; color = :orange)))
end

@testset "TraitMakie: recipes with children" begin
    f = figure()
    s = stairs!(f, [0.0, 1.0, 2.0], [1.0, 3.0, 2.0]; step = :pre)
    @test s isa Stairs && s.line isa Lines
    @test datalim(f, 1) == (0.0, 2.0, 1.0, 3.0)
    @test PC.steppoints(Dynamic{Positions}([0.0 1.0; 1.0 3.0]), :pre) == [0.0 1.0; 0.0 3.0; 1.0 3.0]
    @test PC.steppoints(Dynamic{Positions}([0.0 1.0; 1.0 3.0]), :post) == [0.0 1.0; 1.0 1.0; 1.0 3.0]
    @test PC.steppoints(Dynamic{Positions}([0.0 1.0; 1.0 3.0]), :center) == [0.0 1.0; 0.5 1.0; 0.5 3.0; 1.0 3.0]
    h = hist!(f, [1.0, 2.0, 2.0, 4.0]; bins = 3)
    @test h isa Hist && h.bars isa Bars
    @test datalim(f, 2) == (1.0, 4.0, 0.0, 2.0)       # three bins of width 1 from 1 to 4; the highest has 2
    h.bins = 1                                          # the child follows the parent's attributes
    @test datalim(f, 2) == (1.0, 4.0, 0.0, 4.0)
    @test h.bars.width == 3.0
    b = band!(f, [0.0, 1.0], [0.0, 0.0], [1.0, 2.0])
    @test datalim(f, 3) == (0.0, 1.0, 0.0, 2.0) && b.poly isa Poly
    poly!(f, [0.0, 1.0, 0.5], [0.0, 0.0, 5.0])
    @test datalim(f, 4) == (0.0, 1.0, 0.0, 5.0)
    t = text!(f, 0.5, 6.0, "top")
    @test t isa Labels && datalim(f, 5) == (0.5, 0.5, 6.0, 6.0)
    # a user's recipe with children, made of the library's recipes
    r = plot!(f, Ribbon([0.0, 1.0, 2.0], [1.0, 2.0, 1.0], 0.5; color = :red))
    @test r isa Ribbon && datalim(f, 6) == (0.0, 2.0, 0.5, 2.5)
    recolor!(f, 6, :green)
    @test isfile(save(png("recipes_user"), f))
end

@testset "TraitMakie: attributes changed at the prompt (p.color = x)" begin
    xs = collect(1.0:10.0)
    f = figure()
    p = scatter!(f, xs, xs)
    @test p isa Scatter && p.color isa Kept{ColorSpec} && !getfield(p.color, :compiled)   # the library's default at its bound
    for c in (:red, (0.1, 0.2, 0.3), (0.1, 0.2, 0.3, 0.5), [:red, :blue, :red, :blue, :red, :blue, :red, :blue, :red, :blue],
              [(0.0, 0.0, 0.0, 1.0) for _ in xs], Gradient((1.0, 0.0, 0.0, 1.0), (0.0, 0.0, 1.0, 1.0), 10))
        p.color = c                                      # each a different shape of colour
        @test isfile(save(png("color"), f))
    end
    @test PC.rgba(p.color, 10) == (0.0, 0.0, 1.0, 1.0)
    for m in (:rect, :cross, [isodd(i) ? :diamond : :utriangle for i in 1:10], Star(5), :circle)
        p.marker = m                                     # each a different shape of marker
        @test isfile(save(png("marker"), f))
    end
    p.markersize = 12                                    # a plain field converts as Julia converts
    @test p.markersize === 12.0
    p.pos = (xs, xs .^ 2)                                # new data, of another shape
    @test datalim(f, 1) == (1.0, 10.0, 1.0, 100.0)
    p.pos = Trajectory("t", [(0.0, 0.0), (2.0, 3.0)])     # of the user's type
    @test datalim(f, 1) == (0.0, 2.0, 0.0, 3.0)
    s = stairs!(f, xs, xs)
    s.step = :post
    s.color = :orange
    @test isfile(save(png("stairs"), f))
    @test PC.rgba(s.line.color, 1) == PC.NAMED[:orange]  # the child took the parent's colour at the render
    # names that do not exist are refused where they are given, and the message lists the choices
    e = try; p.color = :magenta; nothing; catch e; e; end
    @test e isa ArgumentError && occursin(":purple", e.msg) && occursin("ColorSpec", e.msg)
    e = try; p.marker = :hexagon; nothing; catch e; e; end
    @test e isa ArgumentError && occursin(":diamond", e.msg)
    @test_throws ArgumentError scatter!(f, xs, xs; color = :magenta)
    @test_throws ArgumentError stairs!(f, xs, xs; step = :sideways)
    @test_throws ArgumentError hist!(f, xs; bins = 0)
    @test_throws DimensionMismatch lines!(f, xs, xs[1:3])
    @test_throws TraitWorld.TraitBoundError (p.color = "red")    # a value of no conforming type: refused at the bound
    s.step = :sideways                                   # a field without a bound is not checked when set,
    @test_throws ArgumentError save(png("bad"), f)       # but at the next render, naming the choices
end

@testset "TraitMakie: live sources" begin
    lv = Live([0.0 0.0; 1.0 1.0])
    f = lines(lv)
    @test datalim(f, 1) == (0.0, 1.0, 0.0, 1.0)
    lv[] = [0.0 5.0; 3.0 1.0; 4.0 2.0]                   # replaced: the plot reads the current value
    @test datalim(f, 1) == (0.0, 4.0, 1.0, 5.0)
    n = Ref(0)
    onchange(_ -> (n[] += 1; save(png("live"), f)), lv) # redrawn on each change
    lv[] = [0.0 0.0; 9.0 9.0]
    @test n[] == 1 && isfile(png("live"))
    sv = Live([1.0, 2.0, 3.0])
    h = hist!(f, sv; bins = 2)
    sv[] = [0.0, 10.0]
    @test datalim(f, 2) == (0.0, 10.0, 0.0, 1.0)
    sn = Sensor("s", [(0.0, 0.0)])                       # a user's source, mutated in place
    scatter!(f, sn)
    push!(sn.readings, (20.0, -3.0))
    @test datalim(f, 3) == (0.0, 20.0, -3.0, 0.0)
    @test isfile(save(png("live2"), f))
end

include("figures.jl")
@testset "TraitMakie: reference images, and PlainPlots the same" begin
    refdir = joinpath(@__DIR__, "references")
    update = get(ENV, "TRAITMAKIE_UPDATE_REFERENCES", "0") == "1"
    tm, pp = reference_figures(TraitMakie), reference_figures(PlainPlots)
    for ((name, f), (_, g)) in zip(tm, pp)
        a, b = save(png("tm_" * name), f), PlainPlots.save(png("pp_" * name), g)
        @test pngdiff(a, b) == 0.0                       # the control draws the same pixels
        ref = joinpath(refdir, name * ".png")
        if update || !isfile(ref)
            mkpath(refdir); cp(a, ref; force = true)
            @info "reference image written" ref
        else
            @test pngdiff(a, ref) <= 1e-3                # the reference, up to font rendering
        end
    end
end

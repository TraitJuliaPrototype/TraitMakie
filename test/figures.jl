# The reference figures: the same calls against TraitMakie or PlainPlots (module `L`), so that
# the two libraries' PNGs can be compared with each other and with test/references/*.png.
# Deterministic data only. Used by runtests.jl and scripts/references.jl.
function reference_figures(L::Module)
    figs = Pair{String,Any}[]
    xs = collect(range(0.0, 2pi; length = 40))

    f = L.lines(xs, sin.(xs); title = "lines and markers", xlabel = "x", ylabel = "sin, cos")
    L.scatter!(f, xs, cos.(xs); color = [(0.2, 0.4, 0.8, 1.0) for _ in xs], markersize = 8)
    L.scatter!(f, xs[1:2:end], sin.(xs[1:2:end]); color = :red, marker = :rect, markersize = 7)
    L.scatter!(f, xs[2:4:end], 0.5 .* sin.(xs[2:4:end]); color = [isodd(k) ? :green : :orange for k in 1:10],
               marker = [isodd(k) ? :diamond : :utriangle for k in 1:10], markersize = 9)
    L.scatter!(f, [1.0, 2.0, 3.0], [-0.8, -0.8, -0.8]; color = (0.1, 0.1, 0.1), marker = :cross, markersize = 10)
    push!(figs, "lines_markers" => f)

    x = [mod(0.37 * i^1.3, 7.0) for i in 1:200]                 # TraitReport's plot: a histogram and its mean
    h = L.hist(x; bins = 24, title = "histogram", size = (1200, 800))
    L.vlines!(h, sum(x) / length(x); color = :red)
    push!(figs, "hist_mean" => h)

    g = L.figure(; title = "recipes with children", xlabel = "t", ylabel = "value")
    L.band!(g, xs, sin.(xs) .- 0.3, sin.(xs) .+ 0.3)
    L.stairs!(g, xs[1:4:end], sin.(xs[1:4:end]); step = :pre, color = :purple)
    L.stairs!(g, xs[1:4:end], sin.(xs[1:4:end]) .- 1; step = :post, color = :green)
    L.stairs!(g, xs[1:4:end], sin.(xs[1:4:end]) .+ 1; step = :center, color = :orange)
    L.poly!(g, [4.5, 5.5, 5.0], [1.2, 1.2, 1.8]; color = (0.9, 0.3, 0.3, 0.6))
    L.text!(g, 5.0, -1.6, "a label"; align = :center, fontsize = 13)
    L.text!(g, [0.5, 1.5], [1.7, 1.7], ["left", "right"]; align = :right, color = :blue)
    push!(figs, "recipes" => g)

    c = L.figure(; title = "attributes changed")                    # every change after the plot was made
    p = L.scatter!(c, xs, sin.(xs))
    p.color = [k <= 20 ? :red : :blue for k in eachindex(xs)]
    p.marker = :diamond
    p.markersize = 9
    s = L.stairs!(c, xs[1:4:end], cos.(xs[1:4:end]))
    s.step = :center
    s.color = (0.2, 0.6, 0.2)
    s.linewidth = 3
    hh = L.hist!(c, [0.5, 1.0, 1.0, 2.0, 2.5, 3.0, 3.0, 3.0]; bins = 3)
    hh.bins = 6
    hh.color = :gray
    l = L.lines!(c, [0.0, 1.0], [0.0, 0.0])
    l.pos = (xs, 0.5 .* cos.(xs))
    L.recolor!(c, 4, :orange)
    push!(figs, "changed" => c)

    lv = L.Live([(0.0, 0.0), (1.0, 1.0)])                          # live data, after two updates
    lf = L.lines(lv; title = "live")
    sv = L.Live([1.0, 2.0, 2.0, 3.0])
    L.hist!(lf, sv; bins = 3, color = (0.12, 0.35, 0.8, 0.4))
    lv[] = [(Float64(i), Float64(i % 3)) for i in 0:6]
    sv[] = [Float64(i % 5) for i in 1:30]
    push!(figs, "live" => lf)
    return figs
end

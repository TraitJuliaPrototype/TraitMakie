# A scripted interactive session (a correctness check, not a timing): fed line by line to a real
# REPL on a pseudo-terminal by scripts/session.sh. A user plots, defines a new data type, a new
# colour, a new plot type (a recipe with children) at the prompt, changes attributes of plots
# already made, and updates live data. Each `_ok` prints "CHECK <what> ok" or "... FAIL".
using TraitMakie, TraitWorld
_ok(what, c) = println(c === true ? "CHECK $what ok" : "CHECK $what FAIL")
OUT = mktempdir(); xs = collect(range(0.0, 2pi; length = 50));
png(n) = joinpath(OUT, n * ".png")
f = lines(xs, sin.(xs); title = "session", xlabel = "x")
p = scatter!(f, xs, cos.(xs))
save(png("1"), f); _ok("first PNG", filesize(png("1")) > 1000)
# a new data type: one line
struct Track; name::String; pts::Vector{NTuple{2,Float64}}; end
@implement Positions Track by pts
tr = lines!(f, Track("t", [(0.0, 0.0), (7.0, 2.0)]); color = :green)
_ok("a new data type", TraitMakie.datalimits(f.axis.plots[3]) == (0.0, 7.0, 0.0, 2.0))
# attributes changed on plots already made: colour and marker change shape
p.color = :red
p.marker = :diamond
p.color = [(i / 50, 0.2, 0.5, 1.0) for i in 1:50]
p.markersize = 9
save(png("2"), f); _ok("changed attributes", filesize(png("2")) > 1000 && p.markersize === 9.0)
# a mistake teaches: the message lists the named colours
p.color = :magenta
_ok("a refused colour keeps the old one", TraitMakie.rgba(p.color, 50) == (1.0, 0.2, 0.5, 1.0))
# a new colour type
struct Fade; n::Int; end
TraitMakie.rgba(c::Fade, i::Int) = (0.0, 0.0, 0.0, i / c.n)
@implement ColorSpec Fade
p.color = Fade(50)
save(png("3"), f); _ok("a new colour type", TraitMakie.rgba(p.color, 25) == (0.0, 0.0, 0.0, 0.5))
# a new plot type: a recipe with children (bars for the stems, markers for the tips)
mutable struct Lollipop; stems::Bars; tips::Scatter; end
Lollipop(x, y) = Lollipop(Bars(hcat(x, y), :gray, 0.04), Scatter(hcat(x, y), :red, 9.0, :circle))
function TraitMakie.datalimits(l::Lollipop)
    a, b = TraitMakie.datalimits(l.stems), TraitMakie.datalimits(l.tips)
    return (min(a[1], b[1]), max(a[2], b[2]), min(a[3], b[3]), max(a[4], b[4]))
end
TraitMakie.PlotCore.draw!(l::Lollipop, c::TraitMakie.PlotCore.Canvas, t::TraitMakie.PlotCore.Transform2D) = (TraitMakie.PlotCore.draw!(l.stems, c, t); TraitMakie.PlotCore.draw!(l.tips, c, t))
TraitMakie.PlotCore.setcolor!(l::Lollipop, c::Dynamic{ColorSpec}) = (l.tips.color = c; nothing)
@implement Plot Lollipop
g = figure(; title = "lollipops")
lp = plot!(g, Lollipop([1.0, 2.0, 3.0], [2.0, -1.0, 3.0]))
save(png("4"), g); _ok("a new plot type", TraitMakie.datalimits(g.axis.plots[1]) == (0.98, 3.02, -1.0, 3.0))
lp.tips.marker = :rect
recolor!(g, 1, :blue)
save(png("5"), g); _ok("its attributes changed", TraitMakie.rgba(lp.tips.color, 1) == TraitMakie.PlotCore.NAMED[:blue])
# a library recipe with children, changed after it was made
h = hist!(g, [0.5, 1.0, 1.5, 2.0, 2.5, 2.6]; bins = 5)
h.bins = 2
h.color = (0.2, 0.6, 0.2, 0.5)
save(png("6"), g); _ok("a recipe's attributes", h.bars.width == 1.05)
# live data: the plot reads the current value; a listener redraws
lv = Live([(0.0, 0.0), (1.0, 1.0)])
lines!(g, lv; color = :purple)
onchange(_ -> save(png("7"), g), lv)
lv[] = [(0.0, 4.0), (5.0, -2.0)]
_ok("live data", isfile(png("7")) && TraitMakie.datalimits(g.axis.plots[3]) == (0.0, 5.0, -2.0, 4.0))
_ok("session done", true)

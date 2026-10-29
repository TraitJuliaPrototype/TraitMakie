"""
    MakieCompatStats

The old API's statistics recipes, a group of their own with StatsBase (the lean-core memo §1.2, "What loads when";
X3 slice 4, E-226): upstream's `src/stats/hist.jl` (Makie 0.24.16) included unchanged. `stephist`'s `plot!` calls
`stairs!` (MakieCompat's, upstream's `stairs.jl`) with the parent's `Attributes`: a recipe with a recipe child.
`hist`'s `plot!` calls `barplot!`, which is not here yet. Plain code; the umbrella declares this package a joint
owner, as it does MakieCompat.
"""
module MakieCompatStats
using TraitWorld
import TraitMakie
import StatsBase
import TraitMakie.OldAPI: Plot, plot!, documented_attributes, convert_arguments, Attributes
import MakieCompat: Observable, @recipe, @inherit, argnames, Point2, Point2d, automatic, extrema_nan, AbstractPlot, BarPlot, Heatmap,
                    Voxels, Stairs, stairs!, barplot!
export stephist, stephist!, StepHist, hist, hist!, Hist

include("upstream/hist.jl")

# a precompile workload, as a recipe package would have one: a step histogram of an `Observable`, changed
TraitWorld.@workload begin
    path = tempname() * ".png"
    f = TraitMakie.figure()
    obs = Observable([1.0, 2.0, 2.5, 3.0, 4.5])
    p = stephist!(f, obs; bins = 4)
    TraitMakie.save(path, f)
    obs[] = [0.5, 1.0, 3.0]
    p.bins = 3
    TraitMakie.save(path, f)
    rm(path; force = true)
end

end

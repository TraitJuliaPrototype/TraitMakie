# MakieCompat

The old Makie recipe API above TraitMakie's trait core: X3's slices 1–3 ([the plan](../../../writeup/plans/2026-10-28-x3-waist-slice1.md), E-219). Upstream's `src/basic_recipes/stairs.jl` and `band.jl` from Makie 0.24.16 are in `src/upstream/`, byte for byte, and are included into the module.

What the layer provides, plain code that uses the trait world (`src/MakieCompat.jl`):
- `Plot{F, T}`, `@recipe`, `documented_attributes`, `conversion_trait`, `PointBased`, `plot!`, `Point2`;
- a compute graph with ComputePipeline's author API (`map!(f, p, inputs, output)`, nodes read as `p.name`), recomputed when an input changed;
- `lines!(p, attrs, node)` in an old `plot!`: a core `PlotCore.Lines` child, fed the node's value at each use;
- the hand-over: `Plot{F, T}` implements TraitMakie's `Plot` trait as a family, so an axis keeps old plots beside the core's;
- a precompile workload, as an old recipe package would have one.

The old API's names and types are the umbrella's (`TraitMakie.OldAPI`: `Plot{F, T}`, `plot!`, `documented_attributes`, `conversion_trait`, `shared_attributes`, `lines!`, `lines`); TraitMakie declares this layer a joint owner (`@joint_owners MakieCompat`), so its methods on them are owned (slice 2, E-222). The control, the same layer over PlainPlots, is `../../baselines/MakieCompatPlain/`.

`band.jl` (slice 3, E-223) brought the conversion cascade (a recipe's own `convert_arguments` before its conversion trait), named arguments, `@inherit` from a theme, a mesh leaf (triangles drawn as core polygons) and keyword attributes on leaves. Its pixels equal TraitMakie's own band's.

Not yet: `Attributes` and `Observable` as user types; the conversion cascade's other cases; other recipes.

## How to run

```
julia --project=experiments/x3/env experiments/x3/check.jl <out dir>        # correctness: PNGs against TraitMakie's own stairs
julia --project=experiments/x3/env experiments/x3/costs.jl <core|old> <out dir>   # load, first PNG, after a late DataFrames load
```

## Results (2026-10-28)

julia-1.13 a4e9ad5da9, TraitWorld 03654b6; fresh processes, 2 runs each. Current numbers: [the evidence](../../../writeup/design/evidence.md) §3.

| | TraitMakie's `stairs` | upstream's `stairs.jl` here | with the workload |
|---|---|---|---|
| `using` | 0.31 s | 0.31–0.33 s | 0.31–0.32 s |
| first PNG | 42–43 ms | 749–750 ms | 66 ms |
| after a late `using DataFrames`: next PNG | 6.5–6.6 ms, nothing recompiled | 6.8–7.0 ms, nothing recompiled | 6.8–6.9 ms, nothing recompiled |

The PNGs equal TraitMakie's own `stairs` for `:pre`, `:post` and `:center`, after `step` and `color` change on the plot, and after a recolour through the core.

### Slice 2 (2026-10-28): the control

TraitWorld 38a3abf; fresh processes, 2 runs each (`experiments/x3/costs.jl`).

| | load | first PNG | next PNG after a late `using DataFrames` |
|---|---|---|---|
| TraitMakie's own `stairs` | 0.31 s | 22 ms | 6.5 ms, nothing recompiled |
| upstream's `stairs.jl` here | 0.31–0.32 s | 67–80 ms | 6.9–7.2 ms, nothing recompiled |
| PlainPlots' own `stairs` | 0.13 s | 22 ms | 125 ms, 17 CodeInstances |
| upstream's `stairs.jl` over PlainPlots (MakieCompatPlain) | 0.13 s | 62–64 ms | 164–166 ms, 25 CodeInstances |

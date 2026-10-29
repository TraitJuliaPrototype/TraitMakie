# MakieCompat

The old Makie recipe API above TraitMakie's trait core: X3's slices 1–4 ([slice 1's plan](../../../writeup/plans/2026-10-28-x3-waist-slice1.md), E-219; [slice 4's](../../../writeup/plans/2026-10-29-x3-slice4.md), E-226). Upstream's `src/basic_recipes/stairs.jl` and `band.jl` from Makie 0.24.16 are in `src/upstream/`, byte for byte, and are included into the module.

What the layer provides, plain code that uses the trait world (`src/MakieCompat.jl`):
- `Plot{F, T}`, `@recipe`, `documented_attributes`, `conversion_trait`, `PointBased`, `plot!`, `Point2`;
- a compute graph with ComputePipeline's author API (`map!(f, p, inputs, output)`, nodes read as `p.name`), recomputed when an input changed;
- `lines!(p, attrs, node)` in an old `plot!`: a core `PlotCore.Lines` child, fed the node's value at each use;
- the hand-over: `Plot{F, T}` implements TraitMakie's `Plot` trait as a family, so an axis keeps old plots beside the core's;
- a precompile workload, as an old recipe package would have one.

The old API's names and types are the umbrella's (`TraitMakie.OldAPI`: `Plot{F, T}`, `plot!`, `documented_attributes`, `conversion_trait`, `shared_attributes`, `lines!`, `lines`); TraitMakie declares this layer a joint owner (`@joint_owners MakieCompat`), so its methods on them are owned (slice 2, E-222). The control, the same layer over PlainPlots, is `../../baselines/MakieCompatPlain/`.

`band.jl` (slice 3, E-223) brought the conversion cascade (a recipe's own `convert_arguments` before its conversion trait), named arguments, `@inherit` from a theme, a mesh leaf (triangles drawn as core polygons) and keyword attributes on leaves. Its pixels equal TraitMakie's own band's.

Slice 4 (E-226) brought recipe children, `Attributes` and `Observable`:
- **A recipe with a recipe child:** upstream's `src/stats/hist.jl`, unchanged, in a group of its own, `../MakieCompatStats/` (with StatsBase, which loads only with it). `stephist`'s `plot!` calls `stairs!(plot, Attributes(plot), plot.points; …)`: the tree is `stephist` → `stairs` → a core `Lines`. The umbrella names the group a second joint owner.
- **`Attributes`** (upstream's type, the umbrella's): `Attributes(p)` and `p.attributes` hold references to the plot's attributes, so a child given them follows the parent's changes. A child takes each attribute from the keywords, else from the given `Attributes`, else its default.
- **`Observable`** (Observables.jl's, re-exported by the umbrella) as an argument or an attribute: read at each use; when it notifies, a plain listener marks the plot's nodes stale (an array changed in place and notified is followed).
- Arguments are kept as given and converted again when their value changes; `p.name[]`, `p.name[] = v`, `p[k][] = v`; the cascade ends in the conversion trait (`convert_arguments(P, args...)`), which `hist.jl`'s conversion of a `StatsBase.Histogram` for `stairs` uses.

Not yet: `hist` (it calls `barplot!`; `barplot.jl` is not included); `on` and `lift` of a plot's attribute; `used_attributes`; `SpecApi`; the PlainPlots control for slice 4.

## How to run

```
julia --project=experiments/x3/env experiments/x3/check.jl <out dir>        # correctness: PNGs against TraitMakie's own stairs
julia --project=experiments/x3/env experiments/x3/costs.jl <core|old|plain|plainold|stephist> <out dir>   # load, first PNG, after a late DataFrames load
julia --project=experiments/x3/env experiments/x3/check4.jl <out dir>       # slice 4: stephist, Attributes, Observables
julia --project=experiments/x3/env experiments/x3/census.jl                 # the layer's and the group's methods by ownership
bash experiments/x3/costs4.sh                                               # slice 4's costs; env-nowl has the workloads off
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

### Slice 4 (2026-10-29): a recipe child, `Attributes`, `Observable`

julia-1.13 a4e9ad5da9, TraitWorld 29b6df4; fresh processes, 2 runs each, stock image (`experiments/x3/costs4.sh`, `logs/costs-slice4.log`). `stephist` of an `Observable` with 200 values, 12 bins. Without the workloads: PrecompileTools' `precompile_workload = false` for MakieCompat and MakieCompatStats (`experiments/x3/env-nowl`).

| | load | first PNG | next PNG after a late `using DataFrames` |
|---|---|---|---|
| TraitMakie's own `stairs` | 0.34–0.35 s | 23–24 ms | 6.6–7.0 ms, nothing recompiled |
| upstream's `stairs.jl` here | 0.35–0.36 s | 97 ms | 7.2–7.3 ms, nothing recompiled |
| the same, without the workload | 0.35 s | 876–880 ms | 7.2 ms, nothing recompiled |
| upstream's `stephist` here (MakieCompatStats) | 0.64 s | 21–22 ms | 127–129 ms, 41 CodeInstances |
| the same, without the workloads | 0.57 s | 1,887–1,897 ms | 120 ms, 31 CodeInstances |

- The checks (`logs/check-slice4.log`): every old-style PNG equals TraitMakie's own `stairs` through the same step points, byte for byte (default bins; `bins = 8` with `normalization = :pdf`; the parent's `bins`, `step`, `color` changed after the plot is made; an `Observable` argument replaced, and changed in place then notified; an `Observable` colour; `Attributes` as an argument, as keywords and as the plot's own; `stairs` of a `StatsBase.Histogram` by `hist.jl`'s own conversion). Slices 1–3's checks pass unchanged (`logs/check-slice4-regression.log`).
- The load of `stephist` includes StatsBase's tree (SparseArrays among it): 0.29 s over the layer's.
- The old `stairs`' first PNG with the workload (97 ms) compiles the keyword call for `step` alone; the workload calls it with `step` and `color`.
- After the late load, `stephist` recompiles: its child's arguments are nodes of the parent's untyped graph, so the creation infers over `Any` and compiles abstract instances (among them `hist.jl`'s `convert_arguments(::Type{Stairs}, ::Histogram)`), which DataFrames' `AbstractVector` subtypes invalidate.

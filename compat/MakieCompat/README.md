# MakieCompat

The old Makie recipe API above TraitMakie's trait core: X3's slices 1–4, and the write-up of the Makie port's finish (the workload's path through the core, E-227, E-228; below) ([slice 1's plan](../../../writeup/plans/2026-10-28-x3-waist-slice1.md), E-219; [slice 4's](../../../writeup/plans/2026-10-29-x3-slice4.md), E-226). Upstream's `src/basic_recipes/stairs.jl` and `band.jl` from Makie 0.24.16 are in `src/upstream/`, byte for byte, and are included into the module.

What the layer provides, plain code that uses the trait world (`src/MakieCompat.jl`):
- `Plot{F, T}`, `@recipe` (the `begin` form, and the do-block form with a theme function and `default_theme`), `documented_attributes`, `conversion_trait`, `PointBased`, `plot!`; GeometryBasics' points and shapes (`Point2f`, `Circle`, …), as upstream re-exports them;
- a compute graph with ComputePipeline's author API on `p.attributes` or the plot (`map!` with one or several outputs, `add_input!`, `add_constant!`, nodes read as `p.name` or `p[:name]`), recomputed when an input changed; a plot's parent, and `parent_scene`/`project` from the axis's last render;
- leaves in an old `plot!` (`lines!`, `scatter!`, `linesegments!`, `text!`, `mesh!`): core primitives, fed the nodes' values at each use; numbers as colours go through the leaf's `colormap` and `colorrange`;
- `name(args...)` returns the figure, its axis and the plot (`fig, ax, p = graphplot(g)`);
- the names a recipe package reads from `using Makie`: the old API's, and upstream's user API re-exported from the umbrella (`Figure`, `Axis`, `lines!`, `scatter!`, `hidedecorations!`, `limits!`, `save`), Observables' `Observable`, `on`, `lift`; `Makie` names this module, so a package's `Makie.plot!` reads it. GraphMakie 0.6.6 runs with only its imports changed (`ndport/pkgs/GraphMakie-ports`, branch `ports`);
- an `Observable` in the user API (`lines!(ax, obs)`, a colour): mirrored into the core's `Live`;
- the hand-over: `Plot{F, T}` implements TraitMakie's `Plot` trait as a family, so an axis keeps old plots beside the core's;
- a precompile workload, as an old recipe package would have one.

The old API's names and types are the umbrella's (`TraitMakie.OldAPI`: `Plot{F, T}`, `plot!`, `documented_attributes`, `conversion_trait`, `shared_attributes`; the plotting functions `lines!`, `scatter!`, `text!`, `linesegments!` are the user API's own, one function per name); TraitMakie declares this layer a joint owner (`@joint_owners MakieCompat`), so its methods on them are owned (slice 2, E-222). The control, the same layer over PlainPlots, is `../../baselines/MakieCompatPlain/`.

`band.jl` (slice 3, E-223) brought the conversion cascade (a recipe's own `convert_arguments` before its conversion trait), named arguments, `@inherit` from a theme, a mesh leaf (triangles drawn as core polygons) and keyword attributes on leaves. Its PNG is close to TraitMakie's own band's: 6.6% of the pixels differ, by at most 8 of 255 in a channel (the mesh's triangles against one polygon: antialiased seams inside the fill; `experiments/x3/logs/pngdiff-fixed-slice5.log`). E-223's "pixels equal" came from `tools/pngdiff.jl` reading blank images; the tool is fixed (2026-10-29).

Slice 4 (E-226) brought recipe children, `Attributes` and `Observable`:
- **A recipe with a recipe child:** upstream's `src/stats/hist.jl`, unchanged, in a group of its own, `../MakieCompatStats/` (with StatsBase, which loads only with it). `stephist`'s `plot!` calls `stairs!(plot, Attributes(plot), plot.points; …)`: the tree is `stephist` → `stairs` → a core `Lines`. The umbrella names the group a second joint owner.
- **`Attributes`** (upstream's type, the umbrella's): `Attributes(p)` holds references to the plot's attributes (`p.attributes`, the compute graph, gives a child its attributes and nodes by reference too), so a child given them follows the parent's changes. A child takes each attribute from the keywords, else from the given `Attributes`, else its default.
- **`Observable`** (Observables.jl's, re-exported by the layer) as an argument or an attribute: read at each use; when it notifies, a plain listener marks the plot's nodes stale (an array changed in place and notified is followed).
- Arguments are kept as given and converted again when their value changes; `p.name[]`, `p.name[] = v`, `p[k][] = v`; the cascade ends in the conversion trait (`convert_arguments(P, args...)`), which `hist.jl`'s conversion of a `StatsBase.Histogram` for `stairs` uses.

Not yet: `hist` (it calls `barplot!`; `barplot.jl` is not included); `used_attributes`; `SpecApi`; the PlainPlots control for slice 4; markers other than the core's named ones (glyphs, polygons) and their rotation; dashed lines; text bounding boxes; a leaf's text offset and vertical alignment.

## How to run

```
julia --project=experiments/x3/env experiments/x3/check.jl <out dir>        # correctness: PNGs against TraitMakie's own stairs
julia --project=experiments/x3/env experiments/x3/costs.jl <core|old|plain|plainold|stephist> <out dir>   # load, first PNG, after a late DataFrames load
julia --project=experiments/x3/env experiments/x3/check4.jl <out dir>       # slice 4: stephist, Attributes, Observables
julia --project=experiments/x3/env experiments/x3/census.jl                 # the layer's and the group's methods by ownership
bash experiments/x3/costs4.sh                                               # slice 4's costs; env-nowl has the workloads off
julia --project=experiments/x3/env experiments/x3/check5.jl <out dir>       # the finish: the workload's plotting calls over the core
bash experiments/x3/costs5.sh                                               # its costs and the plotting session against matplotlib; env-nowl5: TraitMakie's workload off
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

julia-1.13 a4e9ad5da9, TraitWorld c39fedc; fresh processes, 2 runs each, stock image (`experiments/x3/costs4.sh`, `logs/costs-slice4.log`). `stephist` of an `Observable` with 200 values, 12 bins. Without the workloads: PrecompileTools' `precompile_workload = false` for MakieCompat and MakieCompatStats (`experiments/x3/env-nowl`).

| | load | first PNG | next PNG after a late `using DataFrames` |
|---|---|---|---|
| TraitMakie's own `stairs` | 0.33 s | 21–22 ms | 6.5–6.6 ms, nothing recompiled |
| upstream's `stairs.jl` here | 0.34 s | 95–97 ms | 6.9–7.1 ms, nothing recompiled |
| the same, without the workload | 0.34–0.35 s | 851–852 ms | 6.7–7.4 ms, nothing recompiled |
| upstream's `stephist` here (MakieCompatStats) | 0.62 s | 21–22 ms | 126–127 ms, 41 CodeInstances |
| the same, without the workloads | 0.55–0.56 s | 1,847–1,878 ms | 118–171 ms, 31 CodeInstances |

- The checks (`logs/check-slice4.log`): every old-style PNG equals TraitMakie's own `stairs` through the same step points, byte for byte (default bins; `bins = 8` with `normalization = :pdf`; the parent's `bins`, `step`, `color` changed after the plot is made; an `Observable` argument replaced, and changed in place then notified; an `Observable` colour; `Attributes` as an argument, as keywords and as the plot's own; `stairs` of a `StatsBase.Histogram` by `hist.jl`'s own conversion). Slices 1–3's checks pass unchanged (`logs/check-slice4-regression.log`).
- The load of `stephist` includes StatsBase's tree (SparseArrays among it): 0.28 s over the layer's.
- The old `stairs`' first PNG with the workload (95–97 ms) compiles the keyword call for `step` alone; the workload calls it with `step` and `color`.
- After the late load, `stephist` recompiles: its child's arguments are nodes of the parent's untyped graph, so the creation infers over `Any` and compiles abstract instances (among them `hist.jl`'s `convert_arguments(::Type{Stairs}, ::Histogram)`), which DataFrames' `AbstractVector` subtypes invalidate.

### The finish (2026-10-29): the workload's path through the core

[The plan](../../../writeup/plans/2026-10-29-makie-finish.md) (E-227, E-228). E-168's plotting calls (`experiments/ttfx/plotting.jl`: `Figure(size = …)`, `fig[r, c]`, `Axis(fig[2, 1]; xscale = log10)`, `lines!(ax, x, y)`, `save(path, fig; px_per_unit = 1)`) run unchanged after `using TraitMakie`. The umbrella maps them to the core: axes in a grid, a `Scale` trait (`identity`, `log10`) kept in each axis, ticks and labels as the scale's operations, Makie's palette cycled per axis. No old-API machinery is on this path. The solutions are the workload's (setting S, saved once in `experiments/x3/data/`).

julia-1.13 bfca89decc, TraitWorld c39fedc, TraitMakie 983f6e1; fresh processes, 2 runs each after a warm-up, stock image (`experiments/x3/costs5.sh`, `logs/costs-slice5.log`). Without the workload: PrecompileTools' `precompile_workload = false` for TraitMakie (`experiments/x3/env-nowl5`).

| | load | first `plot_two` | `plot_one` | `plot_two` again | after a late `using DataFrames`: `plot_two` |
|---|---|---|---|---|---|
| upstream's calls over TraitMakie | 0.34 s | 158–163 ms | 35 ms | 20–21 ms | 20–26 ms, nothing recompiled |
| the same, without TraitMakie's workload | 0.30–0.32 s | 1,135–1,137 ms | 34–35 ms | 20 ms | 20 ms, nothing recompiled |

**The plotting part of a session** (E-228; `session5.jl`, `session5.py`, the same solutions; seconds from before the process starts; the read of the solutions, 0.09 s in Julia, left out):

| | startup | load | first plot (`plot_two`) | second (`plot_one`) | again (`plot_two`) | **session** |
|---|---|---|---|---|---|---|
| TraitMakie, upstream's calls | 0.12 | 0.35–0.36 | 0.156–0.158 | 0.035–0.036 | 0.020 | **0.68–0.69** |
| matplotlib 3.11.2 | 0.01 | 0.33 | 0.530–0.532 | 0.036 | 0.076–0.080 | **0.98–0.99** |

E-168, for comparison: matplotlib's first plot 0.51 s; stock CairoMakie's 1.51 s (load 3.5 s with SciML); TraitMakie's own API in setting D 0.15 s.

- **Checks** (`logs/check-slice5.log`): each PNG of `plotting.jl` equals, byte for byte, the same figure drawn through the core's own functions (`add_axis!`, `add_lines!`, `render_png`). Against upstream CairoMakie's PNGs of E-168: the same sizes (800×600, 800×400), the same axes, curves and colours in the same order, ticks at powers of ten on the log axis (`10⁻⁴` to `10⁴` in steps of two; Makie's in steps of three); 15.7% and 10.1% of the pixels differ (fonts, margins, tick choice), not a criterion. TraitMakie's suite passes with its reference images unchanged (`logs/traitmakie-suite-slice5.log`); slices 1–4's checks pass (`logs/check-slice5-regression.log`).
- **What the first plot compiles** (`firstplot5.jl`, `logs/firstplot-slice5.log`): 154 CodeInstances, 143 of them Base's broadcasting and the session's `plot_two` (the user's own `getindex.(a.u, k)`), 6 TraitWorld's entry of a scale at `add_axis!`'s bound; none of the core's.
- **Without the workload** the first plot compiles the core's path (1.1 s); the workload's upstream calls (two axes, a log axis) bring it to 0.16 s.
- A scale of no conforming type is refused at the bound: `Axis(fig[1, 1]; xscale = sqrt)` raises "Argument 4 of `add_axis!` is bounded by Scale; a value of type typeof(sqrt) conforms to none of them … Scale is implemented by typeof(identity), typeof(log10)".

### R2 (2026-10-29): a third-party recipe package, GraphMakie (E-240)

TraitMakie b68d97a, julia-1.13 bfca89decc, TraitWorld ca92f22; product setting, strict mode off. Not a measurement. The census's items 3–10 (`../../../writeup/plans/2026-10-29-ndport-r1-census.md`).

| | result |
|---|---|
| GraphMakie 0.6.6 on the layer | loads with its imports changed only (6 lines); R1's stand-ins gone |
| the workload's step f and g graph plots against setting M (upstream GraphMakie, CairoMakie) | the 13 digest lines equal: node positions, edge line data, node and edge colours (RGBA × 255), step g's colours at each saved frame, its line and listeners (`../../../ndport/logs/r2-makie/`) |
| GraphMakie's other features (`leaves-probe-1.log`) | node and edge labels, per-edge widths, named markers, a layout as points, attributes changed after the plot, curved edges draw; inner labels, directed graphs' arrows and dashed edges do not (listed under "Not yet") |
| X3's checks of slices 1–5, the plotting session | 51 PNGs byte-equal to the run before (`../../../experiments/x3/logs/check-r2-regression.log`) |
| after a late `using DataFrames`, the old-API leaves' path (`experiments/x3/check_r2_lateload.jl`) | nothing recompiled (0 CodeInstances; `../../../experiments/x3/logs/lateload-r2.log`) |

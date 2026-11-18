# TraitMakie

A plotting library written with traits, with Makie's shape at a small fraction of its size. Data, colours, markers, scales and plots are traits; recipes have children; an attribute can change shape after a plot is made; data can be live. Cairo draws the PNGs. It is the plotting core under the port of GraphMakie, through its compatibility layer.

## The package

- **`PlotCore`** (`src/PlotCore.jl`, `src/colormaps.jl`): the trait module (`@trait_module`).
  - Traits: `Positions` (points by index), `Sample` (values a histogram bins), `ColorSpec` (a colour, or one per point), `Colormap` (a colour for each value in [0, 1]), `MarkerShape` (an outline per point), `Scale` (an axis's scale and its ticks), `Plot` (a recipe: `datalimits`, `draw!`, `setcolor!`).
  - Members: `Matrix{Float64}` (n × 2), `Vector{NTuple{2,Float64}}` and any vector of 2-vectors as positions; `Vector{<:Real}` as a sample; `ColorName`, an RGBA tuple, a vector of either, and `MappedColors` (numbers through a colormap and a range) as colours; `ColormapName` and a vector of RGBA stops as colormaps; `MarkerName` and `Vector{MarkerName}` as markers; `typeof(identity)` and `typeof(log10)` as scales.
  - Plots: the primitives `Lines`, `Scatter`, `Bars`, `VLines`, `Poly`, `Labels`; the recipes with children `Stairs`, `Hist`, `Band`, which rebuild their children from their own data and attributes at each render.
  - A figure with axes in a grid of equal cells; each axis keeps its plots and its scales, and draws limits, ticks, labels and a title.
- **`TraitMakie`** (`src/TraitMakie.jl`): the ordinary layer. `lines`, `scatter`, `barplot`, `hist`, `vlines!`, `stairs`, `band`, `poly`, `text!`, `plot!`, `figure`, `recolor!`, `save`; upstream Makie's user API for figures with axes (`Figure`, `fig[r, c]`, `Axis`, `lines!`, `scatter!`, `linesegments!`, `hidedecorations!`, `limits!`); names checked where they are given, with messages that list the choices; `p.color = x` translated at the attribute's trait; `Live` (members of `Positions` and `Sample` by forwarding to `val`) and `onchange`. Its module `OldAPI` holds the names of the old recipe API.
- **`compat/MakieCompat`, `compat/MakieCompatStats`:** the old Makie recipe API and its statistics recipes above the core, plain code; a package written against Makie (GraphMakie) runs with `using Makie` read as `using MakieCompat`. See `compat/MakieCompat/README.md`.
- **`baselines/PlainPlots`:** the control without traits, with the same algorithms, canvas, interface and features. `baselines/MakieCompatPlain`: the compatibility layer's control.

## How it uses the design

- No trait erases by default (no `@default_dynamic`). An axis keeps the library's plots boxed, `Dynamic{Plot}`, so a plot's drawing is compiled once; a recipe with children boxes its child's data, `Dynamic{Positions}`.
- The drawing loops (`pixels`, `colors`, `drawmarkers`, `binned`, …) take `@specialize` at their trait arguments and are compiled per type of the data; the doors (`add_lines!`, `add_scatter!`, …, `recolor!`) take `@nospecialize` at theirs and are compiled once. A field typed by a trait (`pos::Positions`) keeps what it is given: a member, a box or a wrapper (the tests' "storage keeps the form given").
- The tests bind the wrapper's function with `using TraitWorld.ByType: compiled_for` (`test/runtests.jl`): the library's exported `compiled_for` is still Julia's cast (deviation T-126 of the traits reference).

## Running

From the workspace root:

```sh
source env.sh
julia-next/julia --project=TraitMakie -e 'using Pkg; Pkg.test()'
```

- `TRAITMAKIE_UPDATE_REFERENCES=1` rewrites the reference images in `test/references/`. `test/figures.jl` draws the five reference figures with either library.
- The REPL session, a scripted session at a real prompt: `JULIA=$PWD/julia-next/julia TraitMakie/scripts/session.sh`. Its default Julia is another tree, so set `JULIA`.
- `scripts/rows.jl`, `scripts/baseline.jl`, `scripts/errors.jl`: the timing rows of `HISTORY.md`; `scripts/env/` holds an environment with both libraries.

## Results

The current numbers, each against plain Julia or Python, are in the design repository's `writeup/design/evidence.md`. The suite's last result is in its `writeup/state.md` §3; on `julia-next` the suite has 8 testsets.

- Tests: 77 pass on `julia-unified`, TraitMakie and PlainPlots pixel-identical (2026-11-08, `unified` f90d152208; `experiments/implementation/stack/logs/w104-slice1-TraitMakie.log`). The reference images on this branch are this build's: both libraries' renders differ from the earlier build's references by 0.1–0.9 % of pixels.
- On `julia-next`: the suite's 8 testsets pass; the REPL session 10 of 10 checks ok, with the one expected error (2026-11-18, `next` 02139b2168, TraitWorld 3e64ede; `experiments/implementation/w156/logs/after-makie.log`, `after-makie-session.log`). `scripts/errors.jl` stops at its third case on the build, before and after this branch alike: the library's `@trait_module` takes options only, not `@trait_module module MyRecipes … end` (`experiments/implementation/w156/logs/makie-errors-after.log`).

## The design

- The design: the design repository's `writeup/reference/` (traits, facts, compiler, lowering).
- The lessons of the ports: `writeup/intro/porting.md`.

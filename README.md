# TraitMakie

A plotting library written in the trait world: the second demonstrator that the trait world works for a real, large library. It has Makie's shape at about a twentieth of its size, measured against Makie, against the same algorithms written without traits, and against matplotlib.

Status: step 1 done (session 23): `PlotCore` with `lines` and `scatter`, axes, ticks and labels, a Cairo backend through declared calls, the ordinary interface, tests with a user's data type and colour. The design is in the design repository (`../writeup/notes/`); this library's design is `../writeup/explorations/makie-rewrite.md` (written before keys; `src/PlotCore.jl` is the keys form).

**How it is built (keys):** `Positions`, `ColorSpec` and `Plot` are traits. `Lines` and `Scatter` keep their data and colour as dynamic values; an axis keeps its plots as `Vector{Plot}` (`Vector{Dynamic{Plot}}`); the loops over data are bounded functions, compiled per key when a dynamic value is opened. Cairo stays outside the trait world: its primitives are ordinary functions in `TraitMakie`, reached by declared calls. `lines(x, y)` converts `x, y` explicitly into one value the bounds take (no bounds over several arguments).

## What it demonstrates

Makie 0.24.16, measured in the earlier experiments (`../experiments/interfaces/`):
- its first plot reaches 1,940 distinct methods by dynamic dispatch;
- each new argument type or attribute shape adds 35–84 more;
- a new table type costs 297 ms;
- an ad-hoc session's first PNG takes 15.7–16.2 s, of which Makie's own recompilation, caused by other packages' loads, is the largest part;
- changing a colour from `:red` to a vector of colours fails.

The trait design predicts:
- **Fast first plots in every load order:** work after load ≤ 0.3 s, with a spread under 10% across load orders.
- **No invalidation of the library's compiled code.**
- **Cheap new types and shapes:** tens of dispatch targets, all in listed conformances, and tens of milliseconds for a new user type.
- **Attribute shapes can change:** one dispatch per change.
- **A trimmed binary that renders a PNG.**

## Scope

**Packages:**
- **`PlotCore`,** the trait module:
  - traits: `Coords`, `Positions{2}` (`Float64` and `Float32` families), `ColorSpec`, `Source`, `Plot`, `Backend`, `Transform` (identity, `log10`), `Layoutable`;
  - primitives: lines, scatter (circles, squares), poly (rectangles, polygons), text (Cairo's toy API);
  - recipes: `lines`, `scatter`, `barplot`, `hist`;
  - a typed compute graph, an `Axis` (limits, linear ticks, labels, the `Float32` conversion), a two-cell grid layout;
  - a workload covering every primitive at both position families.
- **`CairoBackend`:** `Backend` for a Cairo PNG surface. Whether Cairo.jl is wrapped or reached through declared calls is decided by the check; either outcome is a result.
- **`Plotting`,** ordinary code: `lines(x, y)`, the current figure, `save`.
- **`UserPlots`,** a user package defining:
  - `Trajectory` (a one-line conformance);
  - `Gradient` (a `ColorSpec`);
  - `Sensor` (a `Source`);
  - a recipe;
  - plus a variant defined at the prompt.

**Baselines:**
- **`PlainPlots`:** the same algorithms and features without traits, using `Dict{Symbol, Any}` attributes, Observables and untyped edges. It separates what the design contributes from what small size contributes.
- **Makie 0.24.16 with CairoMakie,** for the same plots.
- **matplotlib** (`../experiments/interfaces/python/app.py`).

## Measurements

| # | What | Prediction | Measured (session 23; fresh sessions, three runs) |
|---|---|---|---|
| 1 | time to first PNG in a fresh process, load and work separately | work ≤ 0.3 s in every load order | load 0.30–0.41 s; work 0.1–0.22 s alone |
| 2 | load-order independence with CSV, DataFrames, ChurnStorm, BasePirate before, after, or not at all; stock and patched Julia | spread under 10% | CSV and DataFrames before: 0.31–0.33 s; after: 0.37 s stock, 0.08–0.09 s patched. Not yet under 10% |
| 3 | invalidations over each load | none in trait-world code, with the filter | PlotCore: 0 in every order, stock and patched; TraitWorld machinery: 285 stock, 14 patched |
| 4 | cost of a new data type, colour, recipe, from images and from the prompt | tens of ms for a projection | a new data type at the prompt (forwarding): 61–132 ms |
| 5 | dispatch targets, phases A–G of x15/x16 | tens, all listed; 0–2 per new shape | not yet |
| 6 | colour shape change: `:red`, then a vector, then `Gradient` | works | works (`recolor!`): render 20 ms; to a vector 79 ms and to a user's `Gradient` 91 ms at first use (compiling the new shape); back to `:red`/`:blue` 9 ms |
| 7 | `verify_main` from `main` to drawing; `juliac --trim` | closed; a running binary under 20 MB | not yet |
| 8 | errors: bad data, a wrong colour result, an undeclared operation in a recipe | at the entry or the conformance, naming the bound | not yet |
| 9 | run-time cost of dynamic positions: 10⁵-point lines updated 100 times; 50 plots redrawn | within 10% of PlainPlots | not yet |
| 10 | precompile cost and image sizes | larger images, stated | not yet |

**Success:** rows 1–3 and 6–7 hold where PlainPlots fails them. Rows 4, 5 and 9 are reported as numbers, whatever they are.

## Order of work

It starts after TraitDifferentialEquations has its first measurements.
1. `PlotCore` with lines and scatter, `CairoBackend`, rows 1–3.
2. `UserPlots` and rows 4–6.
3. `verify_main` and the trimmed binary (row 7).
4. The remaining primitives and recipes, rows 8–10.

**Prerequisites in TraitWorld:**
- `Dynamic{X}`;
- lenses and trait fields;
- associated types (`Positions{N, T}`);
- definition checking with parameter archetypes;
- printing frames by bound and representation.

**Running on the shared machine:** one Julia job at a time, niced; juliac builds alone, under the memory guard.

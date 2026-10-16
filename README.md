# TraitMakie

A plotting library written in the trait world: the second demonstrator that the trait world works for a real, large library. It has Makie's shape at about a twentieth of its size, measured against Makie, against the same algorithms written without traits, and against matplotlib.

Status: not started. The design is in the design repository (`../writeup/notes/`); this library's design is `../writeup/explorations/makie-rewrite.md`.

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

| # | What | Prediction |
|---|---|---|
| 1 | time to first PNG in a fresh process, load and work separately | work ≤ 0.3 s in every load order |
| 2 | load-order independence with CSV, DataFrames, ChurnStorm, BasePirate before, after, or not at all; stock and patched Julia | spread under 10% |
| 3 | invalidations over each load | none in trait-world code, with the filter |
| 4 | cost of a new data type, colour, recipe, from images and from the prompt | tens of ms for a projection |
| 5 | dispatch targets, phases A–G of x15/x16 | tens, all listed; 0–2 per new shape |
| 6 | colour shape change: `:red`, then a vector, then `Gradient` | works |
| 7 | `verify_main` from `main` to drawing; `juliac --trim` | closed; a running binary under 20 MB |
| 8 | errors: bad data, a wrong colour result, an undeclared operation in a recipe | at the entry or the conformance, naming the bound |
| 9 | run-time cost of dynamic positions: 10⁵-point lines updated 100 times; 50 plots redrawn | within 10% of PlainPlots |
| 10 | precompile cost and image sizes | larger images, stated |

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

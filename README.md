# TraitMakie

A plotting library written in the trait world: the second demonstrator that the trait world works for a real, large library. It has Makie's shape at about a twentieth of its size, measured against Makie, against the same algorithms written without traits, and against matplotlib.

Status: step 1 done (session 23): `PlotCore` with `lines` and `scatter`, axes, ticks and labels, Cairo called directly (wrapping by facts, session 24), the ordinary interface, tests with a user's data type and colour; row 6 (session 23) and the trimmed binary of row 7 (session 25). The rows were reviewed for wrapping by facts in session 26 (`../writeup/reviews/2026-10-17-demonstrators-under-facts.md`). The design is in the design repository (`../writeup/notes/`); this library's design is `../writeup/explorations/makie-rewrite.md` (written before keys; `src/PlotCore.jl` is the keys form).

**How it is built (keys):** `Positions`, `ColorSpec` and `Plot` are traits. `Lines` and `Scatter` keep their data and colour as dynamic values; an axis keeps its plots as `Vector{Plot}` (`Vector{Dynamic{Plot}}`); the loops over data are bounded functions, compiled per key when a dynamic value is opened. Cairo is called directly, as ordinary code; its code is compiled under the facts policy (case B of `../writeup/notes/3-wrapping.md`). `lines(x, y)` converts `x, y` explicitly into one value the bounds take (no bounds over several arguments).

## What it demonstrates

Makie 0.24.16, measured in the earlier experiments (`../experiments/interfaces/`):
- its first plot reaches 1,940 distinct methods by dynamic dispatch;
- each new argument type or attribute shape adds 35–84 more;
- a new table type costs 297 ms;
- an ad-hoc session's first PNG takes 15.7–16.2 s, of which Makie's own recompilation, caused by other packages' loads, is the largest part;
- changing a colour from `:red` to a vector of colours fails.

The trait design predicts:
- **Fast first plots in every load order:** work after load ≤ 0.3 s, with a spread under 10% across load orders.
- **Loads cannot slow the library down:** only a stakeholder of one of its dispatch facts, or a pirate that wins at one, can discard its compiled code.
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
- **`CairoBackend`:** `Backend` for a Cairo PNG surface, calling Cairo.jl directly.
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

| # | What | Prediction | Measured (session 26: `scripts/rows.jl`, one fresh process per cell, CSV, DataFrames and CairoMakie loaded before, after or not at all; single runs) |
|---|---|---|---|
| 1 | time to first PNG in a fresh process, load and work separately | work ≤ 0.3 s in every load order; patched loads no slower than stock | patched: `using TraitMakie` 0.24–0.26 s, first PNG (lines, scatter, save) 62–65 ms. Stock: 0.22–0.28 s and 4.6 s, 11.0 s with the loads before: without piece 5 every session compiles the policy's code, Cairo's included. Session 23, before facts: load 0.30–0.41 s, work 0.1–0.22 s |
| 2 | load-order independence with CSV, DataFrames, ChurnStorm, BasePirate before, after, or not at all; stock and patched Julia | spread under 10% | patched: first PNG 62–65 ms with CSV, DataFrames, CairoMakie before, after or not at all (session 26); 87–97 ms with twelve packages (session 24). Stock: 4.6–11.0 s |
| 3 | policy CodeInstances lost over each load | 0 | patched, under facts (session 24, g2all): 0 over twelve loads in any order |
| 4 | cost of a new data type, colour, recipe, from images and from the prompt, without and after big loads | tens of ms for a type that forwards to a known key | patched: a new data type that forwards, `@implement` 0.61 s and first PNG 27 ms; after big loads `@implement` 1.63–1.68 s, PNG 27–36 ms. A new colour type: `@implement` 0.10–0.15 s, first PNG 114–116 ms, but 6.4 s with the loads before. `@implement` itself, and new keys after big loads, are the open problem (open-issues §4.5). Stock: `@implement` 1.0–1.5 s |
| 5 | dispatch targets for phases A–G of x15/x16: the targets `verify_main` lists, and the run-time sites the policy leaves in PlotCore's code | tens, all listed; 0–2 per new shape | not yet |
| 6 | colour shape change: `:red`, then a vector, then `Gradient` | works | works (`recolor!`), patched, in every order: render 9 ms; to a vector 40–48 ms, to a user's `Gradient` 28–29 ms at first use; to `:purple` 9 ms. Stock: to a vector 95 ms |
| 7 | `verify_main` from `main` to drawing; `juliac --trim` | closed; a running binary under 20 MB | session 25 (`../experiments/aot/`): 4.07 MB, 0.05 s to the PNG, byte-identical to the session's; no holes on normal paths. Built with `--trim=unsafe-warn`; `--trim=safe` reports 26 errors from the machinery's slow paths |
| 8 | errors: bad data, a wrong colour result, an undeclared operation in a recipe | at the entry or the conformance, naming the bound | not yet |
| 9 | run-time cost of dynamic positions: 10⁵-point lines updated 100 times; 50 plots redrawn | within 10% of PlainPlots | not yet |
| 10 | precompile cost, image sizes, image load time (stock and patched) | larger images, stated | not yet |

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
- printing frames by bound and key (done).

**Running on the shared machine:** one Julia job at a time, niced; juliac builds alone, under the memory guard.

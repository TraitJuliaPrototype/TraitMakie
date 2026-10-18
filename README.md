# TraitMakie

A plotting library written in the trait world: the second demonstrator that the trait world works for a real library. It has Makie's shape at a small fraction of its size: traits for data, colours, markers and plots, recipes with children, attributes that change shape after a plot is made, and live data. Cairo draws the PNGs. The library's design is `../writeup/explorations/makie-rewrite.md` (written before keys; `src/PlotCore.jl` is the keys form).

## Status (session 30, 2026-10-18)

- **Step 2 is built and correct.** Nine plot types (lines, scatter, bars, vertical lines, polygons, text, and the recipes with children `stairs`, `hist`, `band`), marker shapes and per-point colours through `Dynamic`, `p.color = x` at the prompt, live data. 61 tests, five reference images, and a scripted REPL session (ten checks) pass.
- **The control is equivalent.** PlainPlots has every feature, and draws the same pixels for all five reference figures.
- **How it ran:** on the Julia build with parts (B) and (C), with `JULIA_TW_COMPILER_FACTS=0` (TraitWorld's own policy) and `JULIA_TW_VIEWCACHE=0`. **Not yet run with the compiler compiling trait modules by facts** (`JULIA_TW_COMPILER_FACTS` unset): every test, check and session needs a rerun there.
- **Nothing was timed in session 30.** The foundation is changing: Julia's compiler gets parts (B) and (C), then (D) (`Dynamic` in the compiler), and TraitWorld's own policy is being removed. The numbers below are from sessions 23–27, under TraitWorld's prototype policy. They are history until re-measured (the list "To measure after (D)").

## What a user sees at the prompt

The user's criterion: interactivity as the user perceives it. A slow import followed by instant plots is fine. A warning that teaches counts as a win.

- **Plots, then changes.** `f = lines(x, y)`, `p = scatter!(f, x, z)`, then `p.color = :red`, `p.color = [(r, g, b, a), …]`, `p.marker = :diamond`, `p.pos = (x, w)`, `h.bins = 12`, `s.step = :center`. Each change shows at the next `save`. A colour or marker changes shape (a symbol, a vector, a user's type) where Makie 0.24.16 fails (`makie-rewrite.md` §1).
- **New types at the prompt.** A data type in one line (`@implement Positions Track`), a colour or marker of the user's own (one method and `@implement`), a recipe of the user's own made of the library's recipes (`plot!(fig, Lollipop(x, y))`).
- **Live data.** `lv = Live(data)`, `lines(lv)`, `lv[] = newdata`: the plot reads the current value at each render; `onchange(_ -> save(path, fig), lv)` redraws on every change. A user's own mutable type works the same way (`Sensor`, in the tests).
- **Mistakes teach.** `p.color = :magenta` raises "unknown colour :magenta. The named colours are :black, :blue, … ; a colour may also be an RGB or RGBA tuple, a vector of colours (one per point), or a value of a type conforming to ColorSpec", and the plot keeps its colour. Unknown markers, steps, alignments and bin counts are refused the same way. A value of no conforming type is refused at the bound ("a String does not conform to ColorSpec"). Earlier (session 27, row 8): bad data refused at the entry naming the bound, a wrong colour result refused at `@implement`, an undeclared operation in a user's recipe reported at its definition.
- **Earlier timings** (session 27, prototype policy, script mode): `using TraitMakie` 0.24–0.28 s, then the first PNG in 18–22 ms in every load order; a new data or colour type 0.10–0.23 s for the conformance and 50–130 ms for its first PNG. Under the criterion that is instant after a cheap import. Re-measure at the REPL after (D).

## Scope: what is in the tree

- **`src/PlotCore.jl`, the trait module.**
  - Traits: `Positions` (points by index), `Sample` (values a histogram bins), `ColorSpec` (a colour per point), `MarkerShape` (an outline per point), `Plot` (a recipe: `datalimits`, `draw!`, `setcolor!`).
  - Conformances: `Matrix{Float64}` (n × 2) and `Vector{NTuple{2,Float64}}` as positions; `Vector{<:Real}` as a sample; `Symbol`, an RGBA tuple, a vector of either as colours; `Symbol` and `Vector{Symbol}` as markers (`:circle`, `:rect`, `:diamond`, `:utriangle`, `:cross`).
  - Primitives: `Lines`, `Scatter`, `Bars`, `VLines`, `Poly`, `Labels`.
  - Recipes with children: `Stairs` (a `Lines`), `Hist` (a `Bars`), `Band` (a `Poly`).
  - An axis with limits, linear ticks, tick labels, a title and axis labels; Cairo called directly.
- **`src/TraitMakie.jl`, the ordinary layer.** `lines`, `scatter`, `barplot`, `hist`, `vlines!`, `stairs`, `band`, `poly`, `text!`, `plot!`, `figure`, `recolor!`, `save`; checked names; attributes translated at their bounds; `Live` and `onchange`; the precompile workload over every recipe.
- **`baselines/PlainPlots`, the control.** The same algorithms, canvas, interface and features without traits: a plot is a kind and a `Dict{Symbol, Any}` of attributes (read and set as properties), an axis holds `Vector{Any}` plots, and each drawing loop runs behind a function barrier.
- **`test/`.** `runtests.jl` (61 tests: a user's data type, colour, marker, live source and recipe with children; attribute changes; refused names), `figures.jl` (the five reference figures, drawn by either library), `references/*.png`.
- **`scripts/`.** `session.jl` and `session.sh` (the REPL session), `rows.jl`, `baseline.jl` and `errors.jl` (the session 26–27 rows), `env/` (an environment with both libraries).

Not in the tree, though `makie-rewrite.md` §9 plans them: a `Coords` trait per argument, `Transform`, `Layoutable` and a grid layout, `AxisValues` (dates, units, categories), a `Backend` trait (Cairo is the one backend, called directly), a typed compute graph (`Node{T}`), a `UserPlots` package (the user's types live in the tests and the session).

## How it is built

- Data, colours, markers and plots are traits. A plot keeps its data, colour and marker as `Dynamic` values: `Lines.color::ColorSpec` in a trait module means `Dynamic{ColorSpec}`. An axis keeps its plots as `Vector{Plot}`, that is `Vector{Dynamic{Plot}}`.
- The loops over data are bounded functions (`pixels(pos::Positions, t)`, `drawmarkers(m::MarkerShape, …)`, `binned(s::Sample, bins)`), compiled per key when a dynamic value is opened.
- **Attributes are fields.** `p.color = x` is Julia's `setproperty!`, which converts `x` to the field's type. The ordinary layer defines that conversion for its traits' `Dynamic` types: the boundary's translation at the bound, after the names are checked. So assignment from the prompt is an entry (`makie-rewrite.md` §8 item 7, settled).
- **Recipes with children** keep their own data and attributes, and rebuild their children from them before each use (`refresh!`). A child therefore follows the parent's attributes and a live source. The recompute is unconditional; a typed compute graph that skips it when nothing changed is an optimization, not needed for correctness.
- **Live data needs no new mechanism.** A `Live` value conforms by forwarding to its `val` field, and a trait object reads the user's object at its offsets, so every render sees the current value. The notification is ordinary code. This settles `makie-rewrite.md` §8 item 3 for pull-based updates: no `Live{X}` bound modifier is needed. What it does not give: a derived value cached between renders and invalidated by the source (that is the compute graph).
- `lines(x, y)` converts `x, y` explicitly into one n × 2 matrix the bounds take (no bound spans several arguments).

## Rows

"Shown" is correctness, session 30. "Earlier" is a measurement under TraitWorld's prototype policy (sessions 23–27; `scripts/rows.jl`, `scripts/baseline.jl`, single runs, script mode, see git history of this file for the full table). After the review of 2026-10-18 (`../writeup/reviews/2026-10-18-implementation-shape.md` §5), rows 1–3 measure the facts mode, a property of the compiler, until the control runs PlainPlots under `--compile-by-facts=all`.

| # | What | Shown (session 30) | Earlier (prototype policy) | Whose property |
|---|---|---|---|---|
| 1 | first PNG after `using` | the session's first PNG | `using` 0.24–0.28 s; first PNG 18–22 ms in every load order (s27) | the compiler's (facts mode) |
| 2 | load-order independence | — | 18.7–19.3 ms after CSV, DataFrames, CairoMakie; PlainPlots 99.5–101 ms (s27) | the compiler's, until the control |
| 3 | compiled code lost to loads | — | 0 over twelve loads (`g2all`, s24, s27) | the compiler's |
| 4 | a new data type, colour, marker, recipe | all four at the prompt (tests, session) | conformance 0.10–0.23 s, first PNG 50–130 ms; 6.4 s after big loads without the system image (s27) | the checks are traits'; the 6.4 s was the prototype's |
| 5 | dispatch targets | — | not measured: `verify_main` does not reach workers in a session | traits' (declared targets) |
| 6 | attribute shapes change | colour: symbol, tuple, vector of symbols or tuples, user's type; marker: symbol, vector, user's type; data, bins, step | colour changes 9–112 ms (s27) | traits' (`Dynamic`) |
| 7 | trimmed binary | — | 4.07 MB, PNG byte-identical, `--trim=unsafe-warn` (s25, step 1's library) | traits' (target lists) |
| 8 | errors that teach | unknown names list the choices; a non-conforming value names the bound | bad data at the entry naming the bound; a wrong `rgba` at `@implement`; an undeclared operation at the recipe's definition (s27, `scripts/errors.jl`) | traits' (checks) and the ordinary layer's |
| 9 | run time of dynamic data | — | 10⁵-point line 97–99 ms per drawing, PlainPlots 97–102 ms: Cairo's stroke (s27) | — |
| 10 | precompile, image size, load | — | 4.6 s, 5.0 MB, 0.28 s (s27, before step 2) | — |
| 11 | recipes with children | `Stairs`, `Hist`, `Band`; a user's `Ribbon` and `Lollipop` | — | traits' (`Plot` over children) |
| 12 | live data | `Live` replaced, a user's `Sensor` mutated in place, `onchange` redraws | — | the reference layout |
| 13 | PNGs against references and the control | five figures pixel-identical to PlainPlots and to `test/references` | — | correctness |

## To measure after (D)

At the REPL (`scripts/session.jl` as the driver), patched build, no system image, view caches off, with and without CSV, DataFrames and CairoMakie loaded first:
- `using TraitMakie`, then the first PNG (rows 1, 2).
- The first PNG of a new data type, colour, marker and user recipe defined at the prompt (row 4), against PlainPlots' one-method equivalents.
- Each attribute change of row 6 and its next render.
- A live update and its redraw (row 12).
- The steady state of every recipe, against PlainPlots (row 9), including a 10⁵-value `hist` whose child is rebuilt at each render.
- Compiled code lost per load, TraitMakie under `traits` against PlainPlots under `all` (rows 2, 3): the control that decides whose property rows 1–3 are.
- Precompile time, image size and load time with the larger workload (row 10).
- `verify_main` and a trimmed binary of the step 2 library, `--trim=safe` (rows 5, 7).

## What TraitWorld should provide

Found while building step 2; TraitMakie works around each without touching the machinery.
- **`Base.convert(::Type{Dynamic{X}}, x) = Dynamic{X}(x)` for every trait.** Assigning a plain value to a `Dynamic{X}` field from ordinary code is a crossing, and should translate at `X` as a bound does. Without it, `setproperty!` on such a field raises a `MethodError` for `convert`. TraitMakie defines three methods per trait (`src/TraitMakie.jl`): the conversion, and two that resolve ambiguities with Base's `convert(::Type{T}, ::T)` and TraitWorld's `convert(::Type{Dynamic{X}}, ::TObj)`. A generic method in TraitWorld needs the same two companions.
- **Forwarding for a whole family.** `@implement Positions Live{T} by val where {T}` is not supported ("forwarding for the whole family: not yet", `TraitWorld/test/like.jl:78`), so `Live` declares one conformance per parameter value (four).
- **The bound error could list the conforming types.** "a String does not conform to ColorSpec" names the bound; listing the declared conformances (`Symbol`, `NTuple{4,Float64}`, …) would name the fix, as the ordinary layer's messages do.

## Running

- Tests: `julia --project=. -e 'using Pkg; Pkg.test()'`. `TRAITMAKIE_UPDATE_REFERENCES=1` rewrites `test/references/`.
- The REPL session: `scripts/session.sh`.
- On the shared machine: one Julia job at a time, niced, under the shared lock; `JULIA_TW_VIEWCACHE=0`.

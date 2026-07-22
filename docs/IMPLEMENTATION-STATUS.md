# Implementation status

Living summary of what is actually built, to complement the (aspirational) planning docs.
Last updated 2026-07-22 (post-plan quality loop + editing/compare/auto-tune features).

## Architecture

Native Swift monorepo (see revised D-004):

- `swift/FekthorKit/` — the shared, UI-free engine (SwiftPM). Also builds a headless
  `fekthor` CLI target for testing and batch use.
- `apps/fekthor-macos/` — the SwiftUI macOS app (xcodegen project), depends on FekthorKit.
- `fixtures/inputs/` — sample images.

Build: `npm run engine:build` / `engine:test`, `npm run macos:build`. CLI:
`fekthor process <image> [--mode auto|shapes|strokes|gradient] [--colors N] [--epsilon E] [--out DIR]`;
`auto` is the default.

## Quality-loop session (2026-07-21/22)

Iterative per-class quality passes over the four canonical image types (line art,
flat, logo, 3D), each landed as an independent verified commit:

- **Auto-routing**: `fekthor detect` subcommand prints every Stage-A classifier
  feature; new `flatCoverage24` + `bandiness` features and a soft-flat gate route
  rich-palette AI flat art to Shapes (it previously fell into Gradient).
- **Colour**: painted soft shadows survive AA pruning via a spatial near-edge test
  (AA hugs strong edges; shadows do not); large away-from-edge near-tones join the
  palette at a reduced separation floor (flat beard two-tone at low Simplicity).
- **Path refinement**: arc fits are validated against the polyline as well as
  points-to-circle, killing degenerate half-disc/D-ring artifacts from
  ill-conditioned Kåsa fits on straight edges (every fixture improved).
- **Strokes welding**: junction node clusters are unioned (1px radius) so all ends
  of one visual junction compete; continuations score tangent dot minus a
  curvature-continuity penalty with a rivalry veto; ~10px tangent windows see
  through the shared middle segment of shallow X-crossings; near-straight pairs
  only weld above dot 0.9. Junction hooks/dog-legs on stripes are gone.
- **Gradient (3D class)**: texture-adaptive Kuwahara flattening (pass count from a
  measured texture-density score; smooth paintings untouched), radial-quadratic
  moment model for border-region merges (vignette rings coalesce into one
  background shape), colour-gated speckle absorption, doubled stops + bounded
  radial-centre search for large regions. thor-3d: 721 → 176 paths. Documented
  ceiling: micro-texture floors PSNR ~21 dB for any smooth vector output; a
  structural-fidelity Quality term is an open product decision.

## App/tooling features (same session)

- **Compare modes**: Split / Overlay (opacity slider) / Wipe (draggable divider),
  sharing one synchronized zoom/pan transform.
- **Auto-tune**: deterministic 36-point grid search over Detail/Simplicity/
  Smoothing on a 384px thumbnail, scored by the mode-aware Quality metric; the
  sliders move to the winner (~2.7s).
- **Variable-width stroke envelopes** (opt-in): strokes whose dt-width profile
  genuinely varies (p90/p10 ≥ 1.45, ≥ 1.5px) become one smooth closed outline
  fill following the drawn width — Illustrator width-profile semantics. CLI
  `--variable-width`, app toggle beside Taper.
- **Node editing V1**: engine-side anchor model (`Editing.swift`, unit-tested) —
  enumerate/move anchors with control points following, arc→cubic degrade on
  first edit, closed seams stay welded; app Edit mode with click-select, anchor
  drags, Bézier control-handle levers, per-gesture undo (⌘Z, 50 steps), and
  Done regenerating SVG + preview from the edited document.
- **CLI**: `fekthor detect <input>` (classifier features), `--scale` debug render,
  `--variable-width`.

## Engine (FekthorKit)

Deterministic raster→vector pipeline with a render-back comparison harness (exact-match %,
mean-abs, PSNR) using CoreGraphics. Region tracing is the shared-edge PlanarMap path; the
old Vision contour tracer has been removed.

Conversion modes:

- **Auto** (plan 06, default) — runs a deterministic 256px Stage-A feature classifier
  (`greyness`, `paletteCount`, `flatCoverage`, `gradientEnergy`, `inkFraction`,
  `edgeDensity`) to resolve to Strokes / Shapes / Gradient, with all thresholds named and
  fixture-commented in `AutoMode.swift`. If Stage A is unsure, Stage B runs all three
  concrete modes on the 256px thumbnail, scores them with the unchanged plan-01
  `Quality.score`, and picks the highest `overall`. `Fekthor.Result.resolvedMode` records
  the concrete mode; CLI output prints `mode=auto→…`, `metrics.json` includes
  `resolvedMode`, and eval adds Auto rows with `expectedResolvedMode` / `resolvedModeOK`.
  The macOS app defaults to Auto, shows "Detected: …", displays the resolved mode's
  controls, and caches detection by `imageGeneration` so slider changes do not re-run it.
- **Shapes** — colour quantization → optional **region merge** (Simplicity) → **shared-edge
  planar map** (adjacent regions share boundary points, so no gaps/seams) → per-shared-chain
  geometry refinement and primitive substitution. Logo-tuned auto-colour uses exact bucket
  modes for byte-exact brand colours, transparent PNGs flow through the label map as a
  dedicated skipped label, and high-simplicity merging preserves far-distinct tiny accents.
  Flat fixture baseline: artist-flat/shapes overall 0.726, 502 nodes.
  **Flatten** (plan 07, opt-in, default 0): a hue-weighted Oklab metric collapses shade
  families (a beard's blonds, a face's skins) into flat colours — quantize fine → palette
  family clustering (complete-linkage under the metric, dominant-shade representative) →
  region merge with the metric emitting the dominant flat colour → group same-colour
  regions into one face. `thor-3d` at Colours 12 / Flatten 70% → 11 flat fills reading as
  flat art (cape red distinct from background red, black eyes). Flatten 0 is byte-identical
  to the pre-plan pipeline; Strokes/Gradient are unaffected.
- **Strokes** — auto-detects line art vs colour. Line art: foreground threshold → Zhang-Suen
  thinning → skeleton-graph tracing → **tangent-based edge merging** (a line crossing another
  stays one stroke) → **per-stroke width** (median of 2×dt from the exact Euclidean distance
  transform, junctions excluded) → endpoint extension to visual tips + T-joint gap closing →
  refined single centrelines (~hundreds of nodes). Solid blobs (eyes/dots) are classified by
  dt inradius (resample-robust) and emitted as filled primitives. Colour images:
  **coloring-plate** mode — trace shared boundaries once each into clean single outlines, with
  parallel double-line suppression (grid-hash proximity). Options: Uniform width, Caps
  (round/butt/square), opt-in Taper (narrowing tails → outline fills), Line-colour override.
  Near-grey ink snaps to black.
- **Gradient** (plan 05) — **moment-based region merging** replaces the old colour-threshold
  band merge. A fine (k=64) oversegmentation carries closed-form per-region moments
  (`n, Σx…Σyy` and per-channel `ΣC…ΣCC`); the per-channel planar-fit SSE follows in O(1) and a
  union's moments are element-wise sums, so greedy priority-queue agglomeration (`GradientRegions`)
  evaluates every candidate merge without touching a pixel. Cost = excess plane-fit SSE per
  smaller-region pixel; the Blend slider sets the merge threshold τ. Border-touching regions
  are exempt from area absorption and get a 0.8× cost bias so the background coalesces into one
  shape. Each final region is fit as the best of a **colour-aware linear** (axis = variance-
  weighted mean of the three channel plane gradients), a **radial** (best of centroid / brightest-
  10% / darkest-10% centres), or a **solid** fallback — exported as `<linearGradient>` /
  `<radialGradient gradientUnits="userSpaceOnUse">` and rendered through the shared clip path
  (rsvg matches the CoreGraphics preview pixel-for-pixel). 3D baselines: `thor-3d` overall
  0.232→0.260, `artist-3d` ~0.495 (fidelity held). Note: the PSNR-weighted metric rewards
  region *count*, so the "≤60 fills" minimal-shape target trades against the fidelity floor —
  see plan 05 Attempts.

Key modules: `ColorQuantizer` (fixed + auto/AA-excluding), `ComponentMerge`, `PlanarMap`
(faces + shared boundary chains + shared-chain refinement), `Skeleton` / `SkeletonGraph`
(trace + merge), `GradientRegions` (moment-based PQ agglomeration), `GradientFit`
(linear / radial / solid selection), `Geometry` (Douglas-Peucker + polyline smoothing),
`PathRefine` (typed segment fitting), `PrimitiveDetect` (circle/ellipse/rect), `CGPathBuilder`
(shared CGPath source), `PathBuilder` (legacy Catmull-Rom fallback), `DistanceTransform`
(exact Euclidean EDT, Felzenszwalb–Huttenlocher — stroke widths + spur pruning),
`TaperBuilder` (opt-in tail outline fills), `Rasterizer` (CoreGraphics render-back + scale),
`Comparer`, `SVGExport`, `Document`, `Quality`.

## Geometry refinement (plan 02)

Every mode now converts its dense shared boundary chains into an **intentional typed path**
before export, via `PathRefine`: corner anchors (hard constraints — smoothing never rounds
through them, segment endpoints are never moved so the shared-edge gap invariant holds),
least-squares **line** fitting with a **Straighten** control (scales the line-fit tolerance),
Kåsa **arc** fitting (centre pinned to the anchors' perpendicular bisector so the arc passes
exactly through both), and **Schneider cubic Bézier** fitting (chord-length parameterisation,
≤2 Newton reparameterisation rounds, recursive split, control arms clamped to the span length,
`smoothing`-strength blend toward the chord). `PrimitiveDetect` recognises whole rings that are
truly a **circle / ellipse / (rounded-)rect** and emits real `<circle>`/`<ellipse>`/`<rect>`.
Refinement runs **inside `PlanarMap`, once per canonical shared chain** (extended cache;
reversed for the opposite face) so adjacent fills stay point-identical. `ShapeGeometry`
(`rings`/`refined`/`circle`/`ellipse`/`rect`) on `FillShape` and `refined: RefinedPath?` on
`StrokePath` carry the new geometry. `CGPathBuilder` is the single CGPath source shared by the
Rasterizer, and `SVGExport` emits matching `L`/`A`/`C` + primitive elements — verified
identical against librsvg, so **preview == export**. New UI: a **Straighten** inspector slider.

## Quality metrics & eval (plan 01)

`Quality.score` gives a mode-aware `QualityScore` (`fidelity`, `simplicity`, `overall =
0.75*fidelity + 0.25*simplicity`, plus a `detail` map of raw sub-metrics), wired into
`Fekthor.Result.quality` and shown as one honest overall percentage in the app for every
mode. Fidelity per mode: Shapes = ½ exact-pixel + ½ edge alignment (Sobel edge maps
compared with an O(n) two-pass 3-4 chamfer distance transform); Strokes = chamfer between
line masks (dark ink for line art, source edges otherwise); Gradient = PSNR-weighted with
a loose exact-pixel term. `fekthor eval [--fixtures DIR] [--out DIR] [--json]` runs Auto plus
the three concrete modes over every fixture at 1024 working size, prints an aligned table
and writes per-run artefacts; `--json` emits a deterministic `report.json`. Regression
floors live in `EvalRegressionTests`. Note: this plan also fixed a latent cross-process
non-determinism (per-process `Set`/`Dictionary` iteration order in `ComponentMerge` and
`PlanarMap`) so identical runs now produce byte-identical SVG (invariant #1).

## Controls

- **Mode** — Auto / Shapes / Strokes / Gradient. Auto is the default and shows the resolved
  concrete mode's controls.
- **Resolution** — Fast 512 / Balanced 1024 / Detailed 2048; imports are downscaled to a
  working image before vectorising (fast, avoids node explosions on large sources).
- **Auto colours** — detect dominant flat colours and exclude anti-aliasing blends; off falls
  back to a fixed count (Colours / Max colours slider).
- **Simplicity** — region-merge strength (Shapes).
- **Detail** — Douglas-Peucker tolerance.
- **Smoothing** — curve strength (0 polygonal … 1 full; blends fitted cubics toward the chord).
- **Straighten** — geometry-refinement strength (near-straight runs collapse to single lines).
- **Logo** (Shapes) — preset toggle that sets Auto colours, tiny-accent colour detection,
  Simplicity 10%, Detail 85%, Straighten 80% and Smoothing 35%; it does not enable hidden
  engine behaviour.
- **Lines from** (Strokes) — Auto / Centreline / Region edges.
- **Line width** (Strokes) — Auto (per-stroke, dt-estimated) or a fixed width for all lines.
- **Uniform width** (Strokes) — when Auto, force every stroke to the median width.
- **Caps** (Strokes) — round / butt / square end caps (SVG + preview).
- **Taper ends** (Strokes) — opt-in; narrowing brush tails become outline fills, body stays a stroke.
- **Line colour** (Strokes) — override the sampled/black line colour (both sources).

## macOS app

Import (open / drag-drop / paste ⌘V), empty-state drop target, live auto-convert with an
inspector sidebar (controls + result metrics + processing loader), synchronized source/vector
comparison with click-drag and two-finger pan, pinch + button zoom (−/%/+/Fit), crisp
high-resolution vector preview, and SVG export.

## Quality (fixtures, 1024 working size, post quality plans)

Geometry refinement cut node counts 50–60% while holding or lifting fidelity; plans 03–04
added stroke quality and logo handling without regressing canonical scores:

- Shapes (artist-flat): overall 0.726, fidelity 0.833, 502 nodes, gap-free, clean
  lines/curves + primitives.
- Shapes (thor-flat): overall 0.393, fidelity 0.501, 5097 nodes; regression floor added at
  baseline −0.03.
- Strokes (artist-lineart): overall 0.845, fidelity 0.977 (was 0.976), 68 paths / ~240 nodes;
  per-stroke widths, endpoints reach the drawn tips, junctions gap-free, blob eyes stay filled
  primitives at both resamples. ~0.3s per conversion (budget 1.5s).
- Gradient (artist-3d): overall 0.495, fidelity 0.606, ~2k nodes / 125 fills (plan 05).
- Gradient (thor-3d): overall 0.260 (was 0.232), fidelity 0.347; radial fills + single-shape
  background. ~0.4–0.7s per conversion (budget 1.5s).
- Preview == export verified against an independent SVG renderer (librsvg / rsvg-convert),
  including radial gradients.

## Testing / CI

`swift test` (64 tests: geometry, quantize determinism + AA exclusion, stroke edge-merge,
gradient paint + radial round-trip, plan 05 (moment-merge 3-element scene, radial-beats-linear,
background single-region, blend monotonicity, gradient determinism), round-trip fidelity,
chamfer/distance-transform known masks, quality
monotonicity, convert determinism, per-fixture eval regression floors, plus plan 02:
line/arc/cubic fitting, corner preservation, smoothing=0 polygonal, reverse round-trip,
arc-direction render, circle/ellipse/rounded-rect primitives, and shared-chain
point-identity, plus plan 04: exact palette modes, transparent-label skipping, synthetic
logo fixtures and high-simplicity small-region preservation, plus plan 06: Stage-A fixture
resolution, ambiguous Stage-B scoring, Auto determinism/resolvedMode and performance budgets).
GitHub Actions builds and tests the engine and builds the macOS app on
`macos-15` (Xcode 16); green on `main`.

## Quality plans

The full quality-plan set in [`docs/plans/`](plans/README.md) is implemented: plans 01–07
cover mode-aware metrics & eval, geometry refinement, Strokes, Shapes+logo, Gradient,
Auto mode and Flatten. CI polling/pushes are handled by the orchestrator after local review.

## Known gaps / next

- **Editor pivot (active):** Fekthor becomes an editor-first product; the P0
  foundation (Model v2, SVG reader/writer round-trip, workfile, editor
  session/canvas, File menu) is specified in
  [`plans/08-editor-p0.md`](plans/08-editor-p0.md) and decisions D-021…D-023.
  The trace-editing batch developed on imageKid's `feat/fekthor-trace` branch
  still needs porting into this repo (plan 08, step 0b).
- Gradient node counts are high on photo-like inputs (band boundaries).
- Bezier-native document (store curves, not just resampled points).
- `.fekthor` workfile v1 exists engine-side once plan 08 step 8 lands; undo/redo
  beyond snapshots and region-level correction UI are not yet implemented.

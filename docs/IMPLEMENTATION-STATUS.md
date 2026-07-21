# Implementation status

Living summary of what is actually built, to complement the (aspirational) planning docs.
Last updated 2026-07-21 (plan 04 — Shapes mode & logo preset — complete).

## Architecture

Native Swift monorepo (see revised D-004):

- `swift/FekthorKit/` — the shared, UI-free engine (SwiftPM). Also builds a headless
  `fekthor` CLI target for testing and batch use.
- `apps/fekthor-macos/` — the SwiftUI macOS app (xcodegen project), depends on FekthorKit.
- `fixtures/inputs/` — sample images.

Build: `npm run engine:build` / `engine:test`, `npm run macos:build`. CLI:
`fekthor process <image> --mode shapes|strokes|gradient [--colors N] [--epsilon E] [--out DIR]`.

## Engine (FekthorKit)

Deterministic raster→vector pipeline with a render-back comparison harness (exact-match %,
mean-abs, PSNR) using CoreGraphics. Region tracing is the shared-edge PlanarMap path; the
old Vision contour tracer has been removed.

Conversion modes:

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
a loose exact-pixel term. `fekthor eval [--fixtures DIR] [--out DIR] [--json]` runs all
three modes over every fixture at 1024 working size (~8s for 5×3), prints an aligned table
and writes per-run artefacts; `--json` emits a deterministic `report.json`. Regression
floors live in `EvalRegressionTests`. Note: this plan also fixed a latent cross-process
non-determinism (per-process `Set`/`Dictionary` iteration order in `ComponentMerge` and
`PlanarMap`) so identical runs now produce byte-identical SVG (invariant #1).

## Controls

- **Mode** — Shapes / Strokes / Gradient.
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

## Quality (fixtures, 1024 working size, post plan 04)

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

`swift test` (60 tests: geometry, quantize determinism + AA exclusion, stroke edge-merge,
gradient paint + radial round-trip, plan 05 (moment-merge 3-element scene, radial-beats-linear,
background single-region, blend monotonicity, gradient determinism), round-trip fidelity,
chamfer/distance-transform known masks, quality
monotonicity, convert determinism, per-fixture eval regression floors, plus plan 02:
line/arc/cubic fitting, corner preservation, smoothing=0 polygonal, reverse round-trip,
arc-direction render, circle/ellipse/rounded-rect primitives, and shared-chain
point-identity, plus plan 04: exact palette modes, transparent-label skipping, synthetic
logo fixtures and high-simplicity small-region preservation). GitHub Actions builds and tests the engine and builds the macOS app on
`macos-15` (Xcode 16); green on `main`.

## Next: quality plans

The next quality leap is fully planned in [`docs/plans/`](plans/README.md) — self-contained
plans written for an implementer without prior context. Plans 01–05 and 07 are implemented
(mode-aware metrics & eval harness, geometry refinement, Strokes, Shapes+logo, Gradient
minimal-regions+radial, Flatten); **plan 06 (Auto mode)** is next. Board cards
FEKTHOR-088…093 track them.

## Known gaps / next

- Gradient node counts are high on photo-like inputs (band boundaries).
- Bezier-native document (store curves, not just resampled points).
- `.fekthor` project format, undo/redo, and region-level correction UI are not yet implemented.

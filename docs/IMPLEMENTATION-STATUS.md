# Implementation status

Living summary of what is actually built, to complement the (aspirational) planning docs.
Last updated 2026-07-20.

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
mean-abs, PSNR) using CoreGraphics; Vision provides contour tracing.

Conversion modes:

- **Shapes** — colour quantization → optional **region merge** (Simplicity) → **shared-edge
  planar map** (adjacent regions share boundary points, so no gaps/seams) → per-shared-chain
  Douglas-Peucker → Catmull-Rom smoothing. Flat fixture ≈ 96% exact / 38dB PSNR, ~1.8k nodes.
- **Strokes** — auto-detects line art vs colour. Line art: foreground threshold → Zhang-Suen
  thinning → skeleton-graph tracing → **tangent-based edge merging** (a line crossing another
  stays one stroke) → constant width (auto or fixed) → smoothed single centrelines (~hundreds of
  nodes, not thousands). Colour images: **coloring-plate** mode — trace the shared boundaries
  between colour regions once each into clean single outlines. Near-grey ink snaps to black.
- **Gradient** — runs on the same gap-free planar map, fitting a multi-stop linear gradient per
  face (least-squares luminance axis + binned mean colours), exported as SVG `<linearGradient>`.
  3D fixture ≈ 30.7dB PSNR.

Key modules: `ColorQuantizer` (fixed + auto/AA-excluding), `ComponentMerge`, `PlanarMap`
(faces + shared boundary chains), `Skeleton` / `SkeletonGraph` (trace + merge), `GradientFit`,
`Geometry` (Douglas-Peucker + polyline smoothing), `PathBuilder` (Catmull-Rom smoothing),
`Rasterizer` (CoreGraphics render-back + scale), `Comparer`, `SVGExport`, `Document`.

## Controls

- **Mode** — Shapes / Strokes / Gradient.
- **Resolution** — Fast 512 / Balanced 1024 / Detailed 2048; imports are downscaled to a
  working image before vectorising (fast, avoids node explosions on large sources).
- **Auto colours** — detect dominant flat colours and exclude anti-aliasing blends; off falls
  back to a fixed count (Colours / Max colours slider).
- **Simplicity** — region-merge strength (Shapes).
- **Detail** — Douglas-Peucker tolerance.
- **Smoothing** — curve strength (0 polygonal … 1 full).
- **Lines from** (Strokes) — Auto / Centreline / Region edges.
- **Line width** (Strokes) — Auto (estimated) or a fixed width for all lines.

## macOS app

Import (open / drag-drop / paste ⌘V), empty-state drop target, live auto-convert with an
inspector sidebar (controls + result metrics + processing loader), synchronized source/vector
comparison with click-drag and two-finger pan, pinch + button zoom (−/%/+/Fit), crisp
high-resolution vector preview, and SVG export.

## Quality (fixtures)

- Shapes (flat): ~96% exact / ~30dB, gap-free, ~1.4k nodes.
- Strokes (line art): clean single lines, ~440 nodes.
- Gradient (3D): ~30.7dB, gap-free.

## Testing / CI

`swift test` (8 tests: geometry, quantize determinism + AA exclusion, stroke edge-merge,
gradient paint, round-trip fidelity). GitHub Actions builds and tests the engine and builds the
macOS app on `macos-15` (Xcode 16); green on `main`.

## Next: quality plans

The next quality leap is fully planned in [`docs/plans/`](plans/README.md) — six in-depth,
self-contained plans (mode-aware metrics & eval harness, geometry refinement with
straightening/arcs/primitives, Strokes, Shapes+logo, Gradient minimal-regions+radial,
Auto mode), written for an implementer without prior context. Board cards
FEKTHOR-088…093 track them.

## Known gaps / next

- Junction handling in Strokes still leaves small cap pile-ups at crossings.
- Gradient node counts are high on photo-like inputs (band boundaries).
- Bezier-native document (store curves, not just resampled points).
- `.fekthor` project format, undo/redo, and region-level correction UI are not yet implemented.

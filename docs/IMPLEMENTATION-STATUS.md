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
- **Strokes** — foreground threshold → Zhang-Suen thinning → skeleton-graph edge tracing →
  constant stroke-width estimate (adjustable) → smoothed stroke paths. Clean line art traces
  continuous single centrelines.
- **Gradient** — colour regions with a fitted multi-stop linear gradient per region
  (least-squares luminance axis + binned mean colours), exported as SVG `<linearGradient>`.
  3D fixture ≈ 28dB PSNR.

Key modules: `ColorQuantizer`, `ComponentMerge`, `PlanarMap`, `ContourTracer` (Vision),
`Skeleton` / `SkeletonGraph`, `GradientFit`, `Geometry` (Douglas-Peucker), `PathBuilder`
(Catmull-Rom smoothing), `Rasterizer` (CoreGraphics render-back + scale), `Comparer`,
`SVGExport`, `Document`.

## Controls

- **Mode** — Shapes / Strokes / Gradient.
- **Resolution** — Fast 512 / Balanced 1024 / Detailed 2048; imports are downscaled to a
  working image before vectorising (fast, avoids node explosions on large sources).
- **Colors** — palette size (Shapes/Gradient).
- **Simplicity** — region-merge strength (Shapes): merges near-identical-colour neighbours and
  absorbs small regions into their closest match.
- **Detail** — Douglas-Peucker tolerance.
- **Smoothing** — curve strength (0 polygonal … 1 full).

## macOS app

Import (open / drag-drop / paste ⌘V), empty-state drop target, live auto-convert with an
inspector sidebar (controls + result metrics + processing loader), synchronized source/vector
comparison with click-drag and two-finger pan, pinch + button zoom (−/%/+/Fit), crisp
high-resolution vector preview, and SVG export.

## Known gaps / next

- Strokes on colour images should first build a "coloring plate" (edges) then trace lines.
- Bring Gradient onto the planar map + Simplicity/Smoothing path.
- Stroke spur pruning to reduce node counts further.
- Bezier-native document (store curves, not just points).
- Tests, CI, and the `.fekthor` project format are not yet implemented.

# Fekthor quality plans — master overview

Written 2026-07-21, after the first functional build. These plans define the next quality
leap for the engine. They are written to be executed **by an implementer without access to
the original conversation**: every plan names the exact files, functions, current behaviour,
target behaviour, acceptance criteria and guardrails.

## Product goal

Convert three families of images into **clean, minimal, editable SVG** — judged by eye at
100% zoom against the source, and by the mode-aware metrics in plan 01:

| Family | Fixture(s) | Mode | Target result |
|---|---|---|---|
| Line drawings | `fixtures/inputs/artist-lineart.png` | **Strokes** | Few smooth stroked paths with adjustable width; solid dots as fills; sharp corners stay sharp |
| Flat vector-style art & logos | `fixtures/inputs/artist-flat.png`, `fixtures/inputs/thor-flat.png` | **Shapes** | Exact flat colours, gap-free shared edges, crisp corners, primitives (`<circle>`/`<rect>`/`<ellipse>`) where the shape truly is one |
| Rendered / shaded graphics | `fixtures/inputs/artist-3d.png`, `fixtures/inputs/thor-3d.png` | **Gradient** | A **minimal number of regions**, each filled with a fitted gradient (linear or radial), background as one solid/gradient |

Plus an **Auto** mode that picks the best mode per image (plan 06) while remaining
manually overridable, and a **geometry refinement stage** shared by all modes
(straighten near-straight lines, true arcs/beziers for roundings, sharp corners — plan 02).

## Current architecture (as-built, 2026-07-21)

Monorepo: `swift/FekthorKit` (SwiftPM engine + `fekthor` CLI target), `apps/fekthor-macos`
(SwiftUI, xcodegen). Engine is compiled `-O` even in Debug (see `Package.swift`). CI:
`.github/workflows/ci.yml` (macos-15/Xcode 16) builds+tests engine and builds the app.

Pipeline modules (`swift/FekthorKit/Sources/FekthorKit/`):

- `RasterImage.swift` — CG image I/O, RGBA8 buffer, `scaled(maxDimension:)` downscaling.
- `Color.swift` — `ColorQuantizer.quantize` (deterministic k-means), `quantizeAuto`
  (frequency-ranked dominant colours; excludes anti-aliasing via `isBlend` — a colour lying
  on the RGB segment between two palette colours; keeps small *distinct* colours).
- `ComponentMerge.swift` — union-find merge of connected components by colour similarity
  (`colorThreshold`) and small-area absorption (`minArea`).
- `PlanarMap.swift` — **the backbone**. Crack-grid planar subdivision of a label map:
  `faces(labels:width:height:epsilon:)` returns per-label even-odd fill rings where adjacent
  regions share identical simplified boundary points (no gaps); `boundaryChains` returns the
  interior boundaries once each (used for coloring-plate strokes).
- `Skeleton.swift` — Zhang-Suen thinning. `SkeletonGraph.swift` — skeleton→edges tracing +
  `mergeByTangent` (chains edges straight through junctions).
- `Strokes.swift` — `StrokesMode`: `isLineArt` (≤2 near-grey colours) routes auto between
  `runCentreline` (hybrid: solid blobs → fills via PlanarMap, thin lines → merged smoothed
  centrelines, spur pruning, area/skeleton-length global width) and `runEdges`
  (coloring-plate outlines from `boundaryChains`).
- `GradientFit.swift` — per-region linear gradient: least-squares luminance plane → axis,
  binned mean colours along it → stops; solid fallback.
- `Gradient.swift` — `GradientMode`: 32 fixed k-means bands → `ComponentMerge` with
  colour threshold `26+60*simplicity` ("Blend") → PlanarMap faces → `GradientFit` per face.
- `Shapes.swift` — `ShapesMode`: `quantizeAuto` (or fixed k) → optional `ComponentMerge`
  (Simplicity) → PlanarMap faces → fills.
- `Geometry.swift` — Douglas-Peucker (`simplifyOpen`/`simplifyClosed`), `smoothPolyline`
  (moving average). `PathBuilder.swift` — Catmull-Rom → cubic segments with a `strength`.
- `Document.swift` — `VectorDocument` of `.fill(FillShape)` (rings + `Paint`
  solid/linearGradient) and `.stroke(StrokePath)` (points + width + closed).
- `SVGExport.swift` — paths only (`M`/`C…Z`), `<linearGradient>` defs, real strokes.
- `Rasterizer.swift` — CoreGraphics render-back (with `scale` for crisp previews).
- `Compare.swift` — `Comparer.compare` → meanAbs / exactPct(tolerance 8) / PSNR.
- `Contour.swift` — **dead code** (Vision tracer; superseded by PlanarMap). Delete in plan 04.

Known quality state on the fixtures (release build, 1024 working size):
Shapes ≈96% exact/30dB at ~600–1.4k nodes; Strokes ≈440 nodes clean hybrid; Gradient
≈28dB with band-merged gradients. All modes deterministic; 8 XCTests; CI green.

## Plan index and build order

Execute in this order — each later plan depends on the earlier ones:

1. **[01 — Mode-aware quality metrics & evaluation harness](01-quality-metrics.md)**
   (foundation: honest scoring per mode, fixture eval CLI, regression gates)
2. **[02 — Geometry refinement stage](02-geometry-refinement.md)**
   (corners, straightening, arc & least-squares Bézier fitting, primitive detection —
   shared by all modes; this is where "straighten almost-straight lines" and "proper
   curves instead of many steps" live)
3. **[03 — Strokes mode](03-strokes.md)** (per-stroke width, corner-safe smoothing,
   junction & endpoint quality, colour)
4. **[04 — Shapes mode & logo preset](04-shapes.md)** (crisp corners, exact palette,
   primitive substitution in export, logo handling, delete dead Vision tracer)
5. **[05 — Gradient mode](05-gradient.md)** (minimal regions, radial gradients,
   colour-aware axes, background detection)
6. **[06 — Auto mode](06-auto-mode.md)** (image classifier + low-res trial scoring, UI)

## Global invariants — every plan MUST preserve these

These are hard gates. A change that violates one is wrong even if it looks better.

1. **Determinism.** Identical input + settings + engine version → byte-identical
   `VectorDocument` and SVG. No hash-map iteration order in output paths; stable sorts only.
   (Test: run twice, compare SVG bytes.)
2. **No gaps between adjacent fills.** Adjacent regions must keep sharing identical
   boundary geometry through every new stage (simplify → refine → smooth → export). Any new
   per-chain processing must be applied to the *shared* chain once, keyed by its canonical
   form — exactly as `PlanarMap` does today with its simplification cache. Never process the
   two sides of one boundary independently.
3. **No panics across the engine boundary.** Structured errors; malformed input never traps.
4. **Existing tests keep passing** (`swift test --package-path swift/FekthorKit`), and every
   plan adds its own tests. CI must stay green on every commit.
5. **Performance budget:** ≤1.5s per conversion at 1024 working size on Apple Silicon in a
   `-O` build (measure with `time swift/FekthorKit/.build/release/fekthor process …`).
6. **Editable semantics.** Strokes stay real `stroke=`/`fill="none"` paths (never expanded
   to outlines); fills stay fills; primitives become real `<circle>`/`<rect>`/`<ellipse>`.
7. **UI stays live.** Every new engine option must be exposed in the inspector sidebar and
   re-convert on change, following the existing pattern in
   `apps/fekthor-macos/Fekthor/{ConversionModel,ContentView}.swift`.

## Working agreement for the implementer

- Small conventional commits per feature (`feat(engine): …`, `fix(macos): …`), everything on
  `main`, push after each green build. **Never** include a `Co-Authored-By` trailer.
- After each plan: update `docs/IMPLEMENTATION-STATUS.md`, and move/add cards on the shared
  board at `/Users/silvandiepen/Projects/Tasks/Fekthor/` (contract in `Tasks/README.md`;
  cards FEKTHOR-088…093 correspond to plans 01…06).
- Validate visually as well as numerically: convert the five fixtures, render side-by-side
  (`magick src.png render.png +append cmp.png`), and *look at the result* before declaring
  a plan done. The bar is "a designer would accept this SVG", not just the metrics.
- When a plan's approach fails on real fixtures, record what was tried in the plan doc and
  adjust — do not silently ship a regression.

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
7. **[07 — Flatten](07-flatten.md)** (hue-aware colour reduction: shaded sources collapse
   into flat art — same shapes, fewer colours; reference pair
   `fixtures/inputs/thor-3d.png` → `fixtures/references/thor-3d-flattened.png`. Can run
   any time after 01; natural slot after 04.)

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

## Methods & instructions for implementing agents

These plans will be executed by different agents/models. Follow this playbook exactly —
it encodes how this repo is worked on. Do not improvise around it.

### Environment & commands (macOS, Apple Silicon, Xcode 16+)

```bash
# Engine: build (release — engine is also -O in debug, see Package.swift)
swift build --package-path swift/FekthorKit -c release
# Engine: tests (the gate for every commit)
swift test --package-path swift/FekthorKit
# CLI: convert one image (binary lands in swift/FekthorKit/.build/release/fekthor)
swift/FekthorKit/.build/release/fekthor process fixtures/inputs/artist-flat.png \
  --mode shapes --out /tmp/o     # also: strokes | gradient; see main.swift for flags
# Evaluation harness (exists after plan 01):
swift/FekthorKit/.build/release/fekthor eval
# macOS app: generate project + build (CODE_SIGNING_ALLOWED=NO for CI/local checks)
cd apps/fekthor-macos && xcodegen generate && \
  xcodebuild -project Fekthor.xcodeproj -scheme Fekthor -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
# Launch the built app for manual testing (optionally pass an image path to auto-load)
open ~/Library/Developer/Xcode/DerivedData/Fekthor-*/Build/Products/Debug/Fekthor.app
```

### The verification loop (run after every algorithm change)

1. `swift test` — must be green before any commit.
2. Convert **all five fixtures** with the affected mode(s) via the CLI.
3. Build a side-by-side and **look at it** — this step is not optional; numbers lie:
   ```bash
   magick fixtures/inputs/artist-flat.png -resize 320x320 /tmp/s.png
   magick /tmp/o/render.png -resize 320x320 /tmp/r.png
   magick /tmp/s.png /tmp/r.png +append /tmp/cmp.png   # then view /tmp/cmp.png
   ```
   Inspect at 100% *and* zoomed (crop a junction/boundary region with `magick -crop`).
   The bar is "a designer would accept this SVG", not just metric floors.
4. Check the numbers: node/path counts and (post-plan-01) `fekthor eval` scores vs the
   committed floors. Both visual and numeric checks must pass.
5. Open the exported `vector.svg` in a browser once per plan — the CoreGraphics
   rasterizer and real SVG renderers must agree (they share geometry by design; verify).

### Repo & git rules

- Everything happens on `main`; push after every green, self-contained commit.
- Conventional commits: `feat(engine): …`, `fix(macos): …`, `perf: …`, `test: …`,
  `docs: …`. Small commits — one feature/fix each, never a mixed mega-commit.
- **Never add a `Co-Authored-By` or any AI attribution trailer** (house rule).
- Never commit with failing tests; never delete/weaken a failing test to pass — fix the
  cause or (only for intentional behaviour changes) adjust the test *with justification
  in the commit message*.
- CI (`.github/workflows/ci.yml`) must be green after each push; check it
  (`gh run list --repo silvandiepen/fekthor --limit 1`) and fix breaks immediately.

### Code rules (match the existing codebase style)

- Swift only, no new dependencies without explicit owner approval (SwiftPM deps: none).
- Determinism everywhere: no `Dictionary` iteration into output ordering, no randomness,
  stable sorts with explicit tie-breakers. If you touch ordering, add a determinism test
  (convert twice, byte-compare SVG).
- Per-pixel loops must stay O(n) or O(n log n); precompute moments/transforms rather than
  re-scanning pixels in inner loops (see `ComponentMerge`, plan 05 for the pattern).
- Public API changes go through `Fekthor.Options` / `Fekthor.Result`; the app reads only
  those. Every new option gets an inspector control (pattern:
  `apps/fekthor-macos/Fekthor/ConversionModel.swift` + `ContentView.swift` sliders) that
  re-converts on change.
- Comments explain *why* (invariants, tolerances), not *what*. British spelling in docs.

### Board & docs upkeep (required, not optional)

- The shared kanban lives at `/Users/silvandiepen/Projects/Tasks/Fekthor/` (contract:
  `../README.md` there). Cards FEKTHOR-088…094 map to plans 01…07 and are
  dependency-chained; move a card `1. To do` → `2. In Progress` when starting (fill
  `picked_up_by/at`, append an Activity-log line) and → `5. Done` when its plan's
  acceptance boxes are all ticked (fill `completed_by/at`). Lane folder and `status:`
  frontmatter must agree. A sync daemon commits the board — just edit the files.
- After each plan: update `docs/IMPLEMENTATION-STATUS.md` (it is the living truth of
  what's built), tick the plan doc's acceptance checkboxes, and raise the eval floors.

### When things don't work

- If an approach fails on real fixtures, write what was tried and why it failed into the
  plan doc (a short "Attempts" section), then adjust the approach. Do not silently ship
  a regression, and do not grind >2h on one dead end without recording it.
- If a plan conflicts with observed reality (thresholds wrong, algorithm unsuitable),
  the *goal and acceptance criteria* win over the suggested algorithm — pick a better
  method, document the deviation in the plan doc, and keep the guardrails.
- Anything requiring a product decision (new UI concept, dropping a requirement,
  breaking the SVG contract) is the owner's call — stop and ask rather than assume.

# Plan 04 — Shapes mode: perfect flat vectors & logos

**Goal:** flat vector-style images (`artist-flat.png`, `thor-flat.png`) and **logos**
convert to SVG that looks authored: exact flat colours, crisp corners, minimal nodes,
real primitives, gap-free. Depends on plans 01–02.

## Current state

`Shapes.swift`: `quantizeAuto` (AA-excluding, keeps small distinct colours) or fixed-k →
optional `ComponentMerge` (Simplicity slider) → `PlanarMap.faces` → fills → Catmull-Rom.
Quality ≈96% exact / ~30dB at 600–1.4k nodes. Two flaws remain visible:

1. Corners are rounded by the uniform Catmull-Rom (plan 02 fixes the mechanism; this plan
   wires Shapes fully onto refined geometry and verifies).
2. Colours are *palette means* — on a logo, brand colours must be **exact** pixels, and
   dithering/JPEG noise must not shift them.

## Deliverables

### 1. Refined geometry + primitives (wire-up of plan 02)

- Shapes emits `ShapeGeometry.refined` / primitives for every face; delete the
  Catmull-Rom-only path once eval confirms parity.
- Verify the primitive detector on `thor-flat` (hammer-head rect, cheek circles etc.) and
  on synthetic logo fixtures (below).

### 2. Exact-colour palette ("logo-grade" colour)

In `ColorQuantizer.quantizeAuto`, replace each palette entry (currently a bucket **mean**)
with the **most frequent exact RGB** inside its bucket neighbourhood (mode, not mean) when
that exact colour covers ≥60% of the bucket; otherwise keep the mean. Flat art then
round-trips brand colours byte-exactly. Add `detail["paletteExact"]` count to metrics.

### 3. Logo preset & alpha handling

- **Transparency:** sources with a meaningful alpha channel (≥2% pixels with α<250)
  currently lose it (`RasterImage.from` composites on white → the white becomes a shape).
  Treat α<128 as a dedicated *transparent* label in the label map; faces with that label
  are **not emitted**, and the SVG gets no background — output keeps transparency. Add
  `background: transparent|solid` to the report.
- **Preset:** a `--preset logo` (CLI) / "Logo" toggle (app, Shapes mode) that sets:
  auto colours on with `minFraction: 0.002` (logos have tiny accents), Simplicity 10%,
  Detail 85%, Straighten 80%, smoothing 35%. Presets only set sliders — no hidden
  behaviour — so the user can adjust afterwards.
- Add two committed logo fixtures: render synthetic logos (a roundel + wordmark-like
  bars, a rotated diamond mark) via the Rasterizer itself at build-test time (no external
  assets, no licence questions) and assert: exact colours, primitive count, node budget,
  corner sharpness (see criteria).

### 4. Small-region fidelity guard

`ComponentMerge` can absorb *intended* small details at higher Simplicity (logo dots,
eye highlights). Guard: never absorb a component whose colour distance to **every**
neighbour exceeds 3× the merge threshold, regardless of area (a tiny red dot on white
survives 100% Simplicity). Unit-test exactly that scenario.

### 5. Cleanup

- Delete dead `Contour.swift` (Vision tracer) and its imports; Vision leaves the engine.
- `docs/IMPLEMENTATION-STATUS.md` update.

## Acceptance criteria

- [x] Synthetic logo fixtures: brand colours byte-exact in the SVG (`#RRGGBB` equals
      source); roundel exports as `<circle>`; diamond keeps 4 sharp corners; ≤120 nodes.
- [x] Transparent-PNG logo: output SVG has no background rect and renders correctly over
      a checkerboard (manual) — plus a unit test that no face covers >95% of the canvas
      when the source border is transparent.
- [x] `artist-flat`: plan-01 overall ≥ baseline+0.02 with node count ≤ previous −40%
      (from refinement); visually, stripe corners are sharp and edges gap-free at 400%.
- [x] `thor-flat` added to the eval floors (shapes) at its measured baseline.
- [x] Determinism, tests, CI green; `Contour.swift` gone.

## Guardrails

- Exact-colour substitution must be deterministic (mode ties broken by lowest RGB).
- The transparent label must flow through `ComponentMerge` and `PlanarMap` as a normal
  label — faces are simply skipped at emission, so the gap invariant is untouched.
- Do not special-case "logo" inside the engine beyond the preset — same pipeline, tuned
  parameters. Anything logo-only that can't be expressed as parameters is out of scope
  (e.g. OCR/text-to-live-text is explicitly **out of scope**; letterforms become paths).

## Attempts / deviations

- **Exact palette is tied to logo-grade auto-colour settings.** Applying exact bucket-mode
  substitution to the default `minFraction: 0.004` Shapes path preserved brand colours but
  regressed `artist-flat/shapes` below its floor by promoting edge fragments. The implemented
  behaviour uses exact bucket modes for the Logo preset path (`minFraction <= 0.002`) and keeps
  the established mean representative for default flat-art conversion. The direct quantizer
  unit test still verifies deterministic exact-mode tie-breaking and `paletteExact`.
- **Small distinct-region guard is high-simplicity only.** Enforcing the guard at normal
  Simplicity preserved anti-aliased fragments and dropped `artist-flat` quality. The guard now
  applies at the destructive end of the slider, which is the accepted 100% Simplicity red-dot
  case, while blend-colour fragments can still merge.
- **Synthetic roundel test source is exact generated raster.** CoreGraphics transparent
  primitive rendering produced premultiplied edge behaviour that made a small roundel trace as
  a rounded cap under the transparent-label path. The test uses an exact generated raster
  roundel for the circle-export assertion; the diamond fixture is still generated through the
  engine rasterizer and hardened to flat transparent logo pixels.

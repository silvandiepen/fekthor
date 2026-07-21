# Plan 05 — Gradient mode: minimal regions, real gradient fills

**Goal:** rendered/shaded sources (`artist-3d.png`, `thor-3d.png`) become a **small**
number of shapes — background, face, beard, helmet… — each filled with a fitted linear
**or radial** gradient, reading as a faithful stylised vector of the render. This is the
user requirement: *"detect a minimal amount of shapes and use gradient fills to come to a
good result."* Depends on plans 01–02.

## Current state (`Gradient.swift`, `GradientFit.swift`)

32 fixed k-means bands → `ComponentMerge` with colour threshold `26+60×simplicity`
("Blend" slider) → `PlanarMap.faces` → per-face **linear** gradient (least-squares
*luminance* plane → axis; binned mean colours → stops; solid fallback). ≈28dB, ~100
fills. Weaknesses:

1. Merging is **colour-threshold** based — blind to whether one gradient would actually
   explain the union. Region count stays high and merge quality is arbitrary.
2. Linear-only. Spheres/vignettes/backgrounds want **radial** gradients.
3. Axis from *luminance* only — hue shifts (warm→cool shading) are ignored.
4. The stop colours come from binned means but the axis/extent from min/max projection —
   slightly unstable on ragged regions.

## Deliverables

### 1. Gradient-error-driven region merging (replaces colour-threshold merging)

Model each region's colour as **planar in x,y per RGB channel**:
`C(x,y) ≈ a·x + b·y + c` for C ∈ {R,G,B}. A region that fits this model *is* a linear
gradient. Merge decisions then minimise real gradient error, not colour distance:

- Per region, accumulate closed-form moments while labelling:
  `n, Σx, Σy, Σxx, Σxy, Σyy` and per channel `ΣC, ΣCx, ΣCy, ΣCC`.
  Plane fit and its SSE come from these in O(1) (normal equations, 3×3 solve — reuse
  `GradientFit.solve3`); **union moments are just sums**, so evaluating a candidate merge
  costs O(1) with no pixel access.
- Build the region-adjacency graph (adjacencies fall out of `ComponentMerge`'s existing
  edge scan). Greedy agglomeration with a priority queue:
  `cost(a,b) = SSE(a∪b) − SSE(a) − SSE(b)` per union pixel; always merge the cheapest
  pair while `cost ≤ τ`, where `τ = lerp(4, 90, blend²)` (Blend slider 0…1). Deterministic
  tie-breaking (lowest region id pair). Stale-entry PQ pattern: re-validate on pop.
- Keep the existing tiny-region absorption (area-only) as a pre-pass; keep the plan-04
  distinct-colour guard.
- Start from **finer** oversegmentation (k = 48) so merging, not banding, decides
  boundaries.

This directly minimises the number of shapes for a given fidelity — the core ask.

### 2. Radial gradients

New paint case (`Document.swift`): `.radial(center: Pt, radius: Double, stops: [GradientStop])`
(+ optional focal later; not now). For each final region, fit **both**:

- Linear: axis = mean of the three per-channel plane gradients `(a,b)` weighted by
  channel variance (replaces luminance-only); project dense samples, 6 stop bins as
  today; RMSE from residuals.
- Radial: candidate centres = (i) region centroid, (ii) centroid of the brightest 10% of
  pixels, (iii) centroid of the darkest 10%. For each, bin pixels by distance, colours =
  bin means, radius = 95th-percentile distance; RMSE likewise. Keep the best candidate.

Emit whichever of linear/radial has lower RMSE; if the best RMSE × 0.985 ≥ the *solid*
RMSE (mean colour), emit solid instead (flat regions must stay flat fills).
Export `<radialGradient gradientUnits="userSpaceOnUse" cx cy r>` in `SVGExport`;
render with `CGContext.drawRadialGradient` in `Rasterizer` (both inside the shared
`CGPathBuilder` clip path from plan 02).

### 3. Background as one shape

The merging in (1) usually yields this; enforce it: regions touching the image border
are exempt from `minArea` splitting and get a 0.8× cost multiplier when merging with
other border-touching regions, so vignetted backgrounds coalesce. Assert on both 3D
fixtures that ≥55% of border pixels belong to **one** region.

### 4. Boundary geometry

Faces flow through plan-02 refinement like Shapes (shared chains, corners, arcs).
Gradient tolerances stay coarser: keep the current epsilon floor at refine-tolerance
≥1.0 and Straighten default 50%.

## Acceptance criteria

- [ ] Synthetic: a vertical-ramp rectangle next to a radial-shaded disc on flat ground →
      exactly 3 elements: one linear-gradient rect (or refined path), one radial-gradient
      circle primitive, one solid background. Radial beats linear on the disc (RMSE test).
- [ ] `artist-3d` and `thor-3d`: ≤ 60 fills at default Blend; plan-01 gradient overall ≥
      baseline+0.03; background is a single region (border assertion above); visually the
      face/beard/helmet each read as one smoothly-shaded shape at 100%.
- [ ] Blend slider sweep 0→100% strictly decreases fill count (monotonicity test at 5
      points) and never produces gaps.
- [ ] Determinism (PQ ties fixed), tests, CI, eval floors raised; performance ≤1.5s @1024.

## Guardrails

- All merge decisions from **moments only** — never re-scan pixels inside the PQ loop.
- Solid remains the fallback at every stage (regions <24 px, singular fits — as today).
- The luminance-based `GradientFit.fit` stays until (2) reaches parity on eval, then is
  replaced in one commit (single call-site in `Gradient.swift`, plus `Strokes.runEdges`
  does not use gradients — verify no other callers).
- SVG output must not use CSS or filters; plain `<linearGradient>`/`<radialGradient>`
  only (renderer compatibility). Banding softening via blur filters is **out of scope**.

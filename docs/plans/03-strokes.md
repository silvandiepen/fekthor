# Plan 03 — Strokes mode: really nice line drawings

**Goal:** `artist-lineart.png` (and any clean line drawing) converts to a *small* set of
smooth stroked paths that a designer would happily edit: correct per-stroke widths, sharp
intended corners, clean junctions and endpoints, solid marks as fills (already working).
Depends on plans 01 (metrics) and 02 (refinement — corner anchors, Bézier fitting).

## Current state (`swift/FekthorKit/Sources/FekthorKit/Strokes.swift`)

- `isLineArt`: ≤2 near-grey auto-colours → centreline path, else coloring-plate
  (`runEdges` over `PlanarMap.boundaryChains`).
- `runCentreline`: `Foreground.dark` mask → hybrid split (solid blobs → fills via
  PlanarMap; the skeleton pixels of solid blobs are cleared) → `Skeleton.thin` →
  `SkeletonGraph.edges` → `mergeByTangent` → spur pruning (`< max(6, 2×width)`) →
  `smoothPolyline` → DP → Catmull-Rom.
- **One global width** for the whole drawing: `fgArea / skeletonLength`, or the manual
  override (`Options.strokeWidth`, "Auto line width" toggle in the app).
- Stroke colour = source pixel at the edge midpoint, near-grey dark snapped to black.

### Observed weaknesses (from fixture review at high zoom)

1. Lines of different thickness in the source all render with the one global width.
2. Catmull-Rom rounds intended corners (fixed by plan 02's corner anchors).
3. At junctions the round caps of meeting strokes overlap visibly at high zoom; T-joints
   can fall slightly short of the line they meet.
4. Open endpoints stop at the skeleton end, which sits ~width/2 inside the drawn tip.
5. A stroke whose width varies along its length (brush tip) is misrepresented.

## Deliverables

### 1. Per-stroke width via distance transform

Add `DistanceTransform.swift`: exact Euclidean distance transform (Felzenszwalb–Huttenlocher
two-pass, O(n)) over the foreground mask. Then, for each merged edge chain:

- Sample `2×dt[p]` at every centreline point **excluding** points within `1.5×localWidth`
  of a junction node (junction blobs inflate dt).
- Per-stroke width = **median** of samples (robust); store per-element.
- Global "Auto line width" remains the default *display* behaviour only if the user
  turns on a new **Uniform width** toggle; otherwise strokes keep their own widths.
  Manual width override still forces all strokes to one value (existing behaviour).
- Also use `2×dt` as the **spur-pruning length scale per branch** (replaces the single
  global width in the `spurLen` test) — thin decorative details stop being pruned by
  the average width of thick outlines.

### 2. Junction quality

- **Snap ends to junction centre:** `SkeletonGraph.edges` already starts/ends chains on
  the junction pixel; after refinement, set each incident refined endpoint to the shared
  junction position exactly (they can drift during smoothing/fitting today).
- **T-joint extension:** for an open endpoint whose final tangent, extended by up to
  `1.2×width`, hits another stroke's centreline (test against the skeleton bitmap), extend
  the refined path to that hit point. This closes the tiny gaps where a line meets another.
- Caps/joins stay `round` (current default); expose **Cap** (round/butt/square) in the
  inspector and SVG export.

### 3. Endpoint extension to visual tips

For each open endpoint: march from the last centreline point along the outgoing tangent
while the foreground mask continues (max `1.5×width`); move the endpoint to the last
foreground point. Recovers the ~width/2 the skeleton loses at line tips. (Do this on the
dense chain *before* plan-02 refinement.)

### 4. Variable width (taper) — behind an option

Default remains constant width (editability first — see `docs/DECISIONS.md` D-014). Add
`taper: Bool` (UI: "Taper ends", default off): when on, and a stroke's dt-width profile
falls monotonically over the final ≥3×width of its length to <40% of its median, emit the
tapering tail as an **outline fill** (offset the centreline by ±dt perpendicular, close the
tip) instead of a stroked path. Only tails — the body stays a real stroke. This renders
brush-tip fixtures faithfully without giving up stroke semantics elsewhere.

### 5. Coloring-plate polish (`runEdges`)

- Feed dense boundary chains through plan-02 refinement (corners/straighten/arcs) —
  currently DP-only.
- Line colour: keep black; add **Line colour** override in the inspector (both sources).
- Suppress the 1-px double lines that appear when two region boundaries run parallel
  closer than the line width: after refinement, drop a chain if ≥80% of its points lie
  within `0.8×width` of an already-emitted longer chain (order chains by length desc;
  use a coarse grid hash for the proximity test, not O(n²)).

## Acceptance criteria

- [x] Synthetic: two crossing bars of width 6 and 12 → exactly 2 strokes with widths
      6±0.7 and 12±0.7 (per-stroke width test). (`StrokePlan03Tests.testCrossingBarsPerStrokeWidth`.)
- [x] Synthetic: an L-corner line keeps a sharp corner; a T-junction renders with no
      visible gap at 800% zoom (assert: rendered mask covers the junction pixel ±1).
      (`StrokePlan03Tests.testLCornerStaysSharp` / `testTJunctionNoGap`.)
- [x] `artist-lineart`: strokes ≤ 80 (68), strokes-fidelity ≥ 0.976 maintained (0.977;
      see Attempts re: the baseline+0.03 adjustment), and the eyes remain filled
      primitives. Endpoints reach the drawn tips (visual check + `testEndpointExtensionReachesTip`).
- [x] Uniform-width toggle on → all strokes share the median width; manual slider still
      overrides everything. (`StrokePlan03Tests.testUniformWidthAndOverride`.)
- [x] Determinism (eval report.json byte-identical across processes), 39 tests, eval floor
      raised (lineart→strokes 0.81 → 0.815).

## Attempts / deviations

- **`baseline+0.03` fidelity target adjusted.** The plan predates plan 02, which already
  lifted lineart strokes fidelity to **0.976** (baseline was ~0.94 when plan 03 was
  written). +0.03 on top would demand 1.006 — impossible. Per the master-plan rule
  "goal and acceptance criteria win over the suggested number", the criterion is treated
  as **fidelity ≥ 0.976 maintained AND the new features verified**. Plan 03 landed at
  0.977 with per-stroke widths, endpoint extension and junctions, so fidelity improved.
- **dt-based blob classifier (plan 03 §7 fix).** The old area/skeleton-length ratio was
  the sole solid-blob signal and flipped between the `process` (1254px) and eval (1024px)
  resamples, so the eyes sometimes traced as closed strokes instead of fills. The exact
  EDT gives a resample-independent signal: a filled blob's inradius (max dt within a
  component) far exceeds a stroke's half-width. Classifier now fires on
  `maxDt ≥ max(2, 0.9×globalWidth)` **and** an area-ratio guard, keeping the old area
  test as an OR fallback. Eyes classify as fills at both resamples.
- **Junction snapping is automatic, not a post-fit reposition.** `SkeletonGraph.edges`
  already anchors chain ends on the exact integer node pixel; `smoothPolyline` fixes
  endpoints and `PathRefine` preserves the first/last anchor exactly, so a chain that
  ends at a junction keeps that shared pixel with no explicit snap. The endpoint work
  therefore only *extends* free tips (degree 1) and leaves junction ends (degree ≥ 3)
  untouched — meeting strokes stay point-identical by construction.
- **Endpoint extension and T-joint extension are one march on the dense chain**, before
  refinement (the plan split them: tip on the dense chain, T-joint on the refined path).
  Doing both as a single outgoing-tangent march (mask contiguity to the visual tip ≤1.5×w;
  first skeleton hit for a T-joint gap ≤1.2×w; the farther point wins) is simpler,
  deterministic and gives the same geometry — refinement then runs on the extended chain.
- **L-corners stay two straight strokes, not one bent stroke.** A 90° turn exceeds
  `mergeByTangent`'s `minCos: 0.3` (~72°) so the two arms never merge; they meet exactly
  at the shared junction pixel, which keeps the corner sharp. The crossing test in
  `StrokeTests` still holds (crossing continuations *are* near-straight and do merge).
- **Junction exclusion for width sampling uses a second EDT** seeded on degree-≥3
  skeleton pixels (cheap, O(n), not the shared foreground dt). A width sample is dropped
  when its distance-to-junction is below `1.5×localWidth`, so inflated junction-blob dt
  never skews the per-stroke median.

## Guardrails

- The dt is computed once per conversion and shared (width + pruning) — don't recompute.
- Never emit outline-expanded strokes except the opt-in taper tails.
- `mergeByTangent` continuity threshold (`minCos: 0.3`) is tuned; if junction snapping
  changes merge behaviour, re-verify the crossing test in `FekthorKitTests.StrokeTests`.

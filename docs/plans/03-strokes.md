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

- [ ] Synthetic: two crossing bars of width 6 and 12 → exactly 2 strokes with widths
      6±0.7 and 12±0.7 (per-stroke width test).
- [ ] Synthetic: an L-corner line keeps a sharp corner; a T-junction renders with no
      visible gap at 800% zoom (assert: rendered mask covers the junction pixel ±1).
- [ ] `artist-lineart`: strokes ≤ 80, plan-01 strokes-fidelity ≥ baseline+0.03, and the
      eyes remain filled primitives. Endpoints of the brush hairs reach the drawn tips
      (visual check + endpoint-extension unit test).
- [ ] Uniform-width toggle on → all strokes share the median width; manual slider still
      overrides everything.
- [ ] Determinism, tests, CI, eval floors raised.

## Guardrails

- The dt is computed once per conversion and shared (width + pruning) — don't recompute.
- Never emit outline-expanded strokes except the opt-in taper tails.
- `mergeByTangent` continuity threshold (`minCos: 0.3`) is tuned; if junction snapping
  changes merge behaviour, re-verify the crossing test in `FekthorKitTests.StrokeTests`.

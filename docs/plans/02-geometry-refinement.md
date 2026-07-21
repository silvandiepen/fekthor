# Plan 02 — Geometry refinement stage (all modes)

**Goal:** replace "many small steps through every point" with *intentional geometry*:
sharp corners stay sharp, almost-straight runs become single straight lines, roundings
become true arcs/Béziers fitted within a tolerance, and whole shapes that are really a
circle/ellipse/(rounded-)rect are recognised as such. One shared stage used by Shapes,
Gradient, Strokes and the coloring-plate — this implements the user requirements
*"if we draw lines which are almost straight, straighten them"* and *"use proper curves
for roundings instead of many steps"*, plus primitive detection.

## Where it sits in the pipeline

Today every mode ends with: Douglas-Peucker points → `PathBuilder` Catmull-Rom (uniform
`smoothing` strength) → export/render. Problems with that:

- Catmull-Rom rounds **everything**, including intended corners (logo corners melt).
- DP output on a straight-but-noisy run is several short segments, not one line.
- A circle becomes ~20 cubic segments through noisy points instead of one clean circle.
- Smoothing strength is global; it cannot straighten.

**New stage:** convert each polyline (already simplified by DP) into a typed
**segment chain** *before* smoothing/export:

```swift
// New file: PathRefine.swift
public enum RefinedSegment: Sendable {
    case line(to: Pt)
    case arc(center: Pt, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool)
    case cubic(c1: Pt, c2: Pt, to: Pt)
}
public struct RefinedPath: Sendable {
    public var start: Pt
    public var segments: [RefinedSegment]
    public var closed: Bool
}
public struct RefineOptions: Sendable {
    public var tolerance: Double        // max deviation from input points, px (drive from Detail)
    public var cornerAngle: Double      // corner if turn angle > this (default 32°)
    public var straighten: Double       // 0…1 UI option; scales line-fit tolerance (default 0.5)
    public var smoothing: Double        // existing smoothing strength for the cubic fallback
}
public enum PathRefine {
    public static func refine(_ pts: [Pt], closed: Bool, options: RefineOptions) -> RefinedPath
}
```

### Algorithm (per polyline, deterministic)

1. **Resample** the DP polyline back to dense samples? **No** — DP already lost data.
   Instead, refinement consumes the **pre-DP dense chain** wherever available:
   - `PlanarMap`: refine each *shared crack chain* (the dense grid points, before
     `Geometry.simplifyOpen`) — replace the DP call inside `PlanarMap` with
     `PathRefine.refine`, keeping the existing **canonical-chain cache** so both
     neighbouring faces get the *same* refined chain (gap invariant, master plan §2).
   - `Strokes`: refine the dense smoothed centreline (`Geometry.smoothPolyline` output)
     instead of DP-then-Catmull-Rom.
2. **Corner detection** on the dense chain: at each point, angle between the mean
   direction of the previous k and next k samples (k = clamp(chainLen/12, 3, 8)).
   Mark a corner where the turn exceeds `cornerAngle` *and* is a local maximum of turn.
   Corner points are **anchors**: no segment may cross an anchor, and smoothing never
   rounds through one. Endpoints of open chains are anchors.
3. **Split** the chain at anchors into spans; fit each span with the first fit that
   stays within `tolerance` (max perpendicular deviation over the span's dense samples):
   a. **Line** — least-squares line through span; tolerance scaled by
      `(0.5 + straighten)`, so the Straighten option makes line-fitting greedier.
      Additionally **axis-snap**: if the fitted line is within 2° of horizontal/vertical
      and `straighten ≥ 0.5`, snap it exactly (endpoints keep their tangential coords).
   b. **Arc** — Kåsa/Taubin circle fit (closed-form least squares) through the span;
      accept if radial deviation ≤ tolerance, radius ≤ 4× span length (reject
      near-straight giant-radius arcs — those are lines), and arc sweep ≥ 15°.
   c. **Cubic Béziers** — least-squares Bézier fitting with recursive split at the
      worst-error point (Schneider's algorithm: endpoint tangent estimation, chord-length
      parameterisation, 1–2 Newton–Raphson reparameterisation rounds, split if error >
      tolerance). This replaces Catmull-Rom as the primary curve representation; the
      existing `PathBuilder` remains only for `smoothing`-strength blending: after
      fitting, if `smoothing < 1`, blend control points toward the polygonal chord by
      `(1−smoothing)` (preserves the existing slider semantics; `smoothing = 0` must
      yield the pure line/polygon result).
4. **Merge pass:** adjacent line segments whose directions differ < 4° merge into one;
   adjacent arcs with same centre (within tolerance) and radius merge.

### Whole-shape primitive detection (closed rings only)

After refinement, attempt in order on each closed ring (dense samples, not segments):

- **Circle:** Taubin fit; accept if max radial deviation ≤ max(tolerance, 1.5% of r).
- **Ellipse:** direct least-squares conic (Fitzgibbon); accept with same deviation rule
  (distance approximated via sampled points on the fitted ellipse).
- **Rect / rounded rect:** exactly 4 line segments (after refinement) with all angles
  90°±4° → rect (axis-aligned if within 2° and `straighten ≥ 0.5`, else a rotated rect
  exported as a path of 4 lines); 4 lines + 4 arcs alternating with equal radii ±20% →
  rounded rect (`<rect rx=…>` when axis-aligned).

Represent in the document (`Document.swift`):

```swift
public enum Element { case fill(FillShape), stroke(StrokePath) }           // existing
public enum ShapeGeometry: Sendable {                                       // new, inside FillShape
    case rings([[Pt]])                       // legacy
    case refined([RefinedPath])              // ring paths after refinement
    case circle(center: Pt, radius: Double)
    case ellipse(center: Pt, rx: Double, ry: Double, rotation: Double)
    case rect(center: Pt, w: Double, h: Double, rotation: Double, cornerRadius: Double)
}
```

`StrokePath` gains `refined: RefinedPath?` alongside `points` (fallback).

### Export & render

- `SVGExport.swift`: emit `L` for lines, `A` for arcs, `C` for cubics; primitives as
  `<circle>`, `<ellipse>`, `<rect>` (with `transform="rotate(…)"` when rotated). Keep
  `fill-rule="evenodd"` by grouping a primitive-outer with path-holes inside a `<path>`
  fallback when a ring set mixes primitive + holes — a primitive is only emitted when its
  ring set is exactly one ring, otherwise use refined paths.
- `Rasterizer.swift`: render the same geometry (CG `addArc`, `addCurve`, ellipse/rect
  transforms) so preview == export. **One code path builds CGPath from geometry — share
  it between Rasterizer and a new `CGPathBuilder` helper so they cannot diverge.**

### UI

- New **Straighten** slider (0–100%, default 50%) in the inspector for all modes →
  `RefineOptions.straighten`. Detail keeps driving `tolerance` (map: tolerance =
  4.2 − 3.9×detail, unchanged). Smoothing keeps its meaning via the blend in 3c.

## Files touched

`PathRefine.swift` (new), `CGPathBuilder.swift` (new), `PlanarMap.swift` (refine shared
chains via cache), `Strokes.swift`, `Shapes.swift`, `Gradient.swift`, `Document.swift`,
`SVGExport.swift`, `Rasterizer.swift`, `Fekthor.swift` (options), app model/view.

## Acceptance criteria

- [ ] Synthetic tests: a noisy straight line (±0.6px jitter) → **1 line segment**; a
      rasterised circle r=40 → `circle` primitive; a rounded-rect raster → `rect` with
      `cornerRadius`; an L-shape keeps a sharp 90° corner at every smoothing setting.
- [ ] `artist-flat` Shapes: the brush handle and stripe boundaries become
      lines/single curves; node count drops ≥ 40% at equal Detail with fidelity within
      1% of pre-refinement (verify with `fekthor eval` from plan 01).
- [ ] `artist-lineart` Strokes: the beret and head outlines are single smooth curves;
      the eyes (fills from the hybrid) become `circle`/`ellipse` primitives.
- [ ] No gaps: zoom to 400% on `artist-flat` boundaries in the app — adjacent fills
      share edges exactly (also assert in a test: for a 2-colour synthetic image, the
      two faces' shared chains are point-identical after refinement).
- [ ] Determinism + all tests + CI green; eval floors from plan 01 raised to the new
      baseline.

## Guardrails

- Refinement must operate **per canonical shared chain** inside PlanarMap (extend the
  existing cache keyed on the canonical chain; the two faces reference one result).
- Corner anchors are hard constraints — document this in code; a future "round corners"
  feature would relax `cornerAngle`, not bypass anchors.
- Arc export: SVG `A` syntax is error-prone (large-arc/sweep flags) — add a round-trip
  test rendering an arc-only SVG via the Rasterizer against a CG-native drawing.
- Keep the legacy `rings`/`points` path working until all modes emit refined geometry,
  then delete Catmull-Rom-only paths in a final cleanup commit.

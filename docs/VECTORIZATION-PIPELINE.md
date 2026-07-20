# Vectorisation pipeline

## Purpose

The central engineering problem is not generating SVG syntax. It is reconstructing the drawing semantics behind raster pixels. A dark region may represent:

- A constant-width stroke.
- A variable-width stroke.
- A closed outline drawn as a stroke.
- A genuinely filled object.
- Several touching strokes.
- Noise, shading or compression artefacts.

The pipeline therefore combines image cleanup, geometric classification, topology recovery, curve fitting and render-back validation.

## Pipeline overview

```text
Source image
  ↓
Normalise and preprocess
  ↓
Foreground / colour segmentation
  ↓
Connected-region analysis
  ↓
Stroke / fill / uncertain classification
  ├── Stroke regions → skeleton → graph → width → Bézier strokes
  └── Fill regions   → contours → holes → Bézier filled shapes
  ↓
Hybrid document assembly
  ↓
Render-back comparison
  ↓
Refinement and simplification
  ↓
Editable vector document
```

## 1. Decode and normalise

The host decodes the image and applies orientation. The core receives a normalised pixel buffer.

Required operations:

- Convert into a known colour space.
- Handle premultiplied alpha correctly.
- Preserve transparent regions.
- Estimate whether the source has a meaningful alpha mask.
- Build a lower-resolution preview pyramid.
- Record the source-to-working transform.

Do not discard the original image or overwrite it with processed pixels.

## 2. Estimate background and foreground

For simple line art, foreground extraction may be based on luminance and alpha. For scans or flat-colour art, the background may be uneven.

Candidate steps:

- Sample image borders and large low-variance regions.
- Estimate one or more likely background colours.
- Compute colour distance from the background.
- Produce a foreground probability map.
- Convert to a binary mask using global or local thresholding.
- Preserve anti-aliased boundaries as confidence rather than treating every pixel as equally certain.

The application should show the cleaned mask in diagnostics because errors here propagate through the complete pipeline.

## 3. Cleanup

Cleanup should remove artefacts without changing intended topology.

Operations include:

- Small connected-component removal.
- Isolated hole removal.
- Gentle opening or closing.
- Gap repair below a configurable distance.
- Edge-preserving denoise.
- Scan shadow compensation.
- User cleanup-mask additions and removals.

Each cleanup operation must be parameterised and reversible. Aggressive morphology can join nearby lines or erase small details, so defaults should be conservative.

## 4. Segment regions

Build connected components from the foreground mask. For colour artwork, segmentation may first cluster colours and then build components within clusters.

For each region, calculate:

- Bounding box.
- Area.
- Perimeter.
- Hole count and nesting.
- Compactness.
- Distance-to-boundary distribution.
- Skeleton length.
- Width median, variance and extrema.
- Endpoint and junction counts from a provisional skeleton.
- Contact with image boundary.
- Neighbouring region and colour relationships.

These measurements support classification and diagnostics.

## 5. Classify stroke versus fill

The deterministic classifier should combine several signals rather than use one threshold.

Stroke-like evidence:

- Region width is small relative to length.
- Width is reasonably consistent.
- Skeleton length is high relative to area.
- Region has endpoints or branch structure.
- Shape is elongated or forms a narrow loop.

Fill-like evidence:

- Region is compact and wide.
- Skeleton collapses into a short or unstable structure.
- Area is large relative to perimeter.
- Region represents a small solid mark, such as a pupil.
- A contour description is substantially simpler than a centreline plus width.

Ambiguity should remain explicit. The classifier emits:

- Class.
- Confidence.
- Feature summary.
- Alternative interpretation score.

A user override takes precedence but does not delete the automatic result.

## 6. Skeletonise stroke regions

Skeletonisation reduces a thick region to a one-pixel-wide centre representation while attempting to preserve topology.

Requirements:

- Preserve connected components.
- Preserve meaningful holes and loops.
- Avoid excessive diagonal stair-stepping.
- Produce stable results under small antialiasing changes.
- Support region-local recomputation.

The research phase should benchmark several thinning and medial-axis approaches. No single method should be assumed correct before testing against the fixture set.

A distance transform should be computed alongside or before skeletonisation. The distance from each skeleton sample to the source boundary provides a local half-width estimate.

## 7. Build a topology graph

Raw skeleton pixels are unsuitable for direct SVG export. Convert them into a graph.

### Node types

- Endpoint: one connected neighbour.
- Chain sample: two connected neighbours.
- Junction: three or more connected neighbours.
- Loop anchor: artificial node inserted into a component without endpoints.

### Edge creation

Walk from node to node and collect ordered pixel samples. Every skeleton pixel should belong to one node neighbourhood or one graph edge.

### Junction neighbourhoods

Pixel skeletons often produce clusters of adjacent junction pixels. Collapse each cluster into one logical junction with a representative position. Preserve the attachment order of incident edges.

### Graph invariants

- Each edge references valid start and end nodes.
- Loop components are represented without losing closure.
- No pixel chain is emitted twice.
- Region connectivity matches the cleaned raster unless explicitly repaired.

## 8. Prune artefacts

Skeletons commonly contain short spurs caused by antialiasing, corners or rough boundaries.

Pruning rules may use:

- Spur length relative to local width.
- Endpoint confidence.
- Render impact if removed.
- Angle with the parent branch.
- Whether the spur reaches a meaningful contour extremity.

Pruning must avoid deleting intended details such as eyelashes, brush bristles or tiny corners. Removed branches should remain available in diagnostics and be recoverable through a lower noise-removal setting.

## 9. Recover stroke width

For each centreline sample, estimate width from the distance transform and local boundary geometry.

Constant-width MVP:

- Use a robust median across the edge.
- Exclude samples near junctions and endpoints.
- Reject outliers.
- Store width confidence.

Variable-width later:

- Smooth local diameter along arc length.
- Preserve intentional tapers.
- Prevent abrupt width oscillations caused by raster noise.
- Represent width as a profile or expand to an outline only when the target format cannot preserve it.

At intersections, width should be inferred from stable samples away from the junction rather than directly from the enlarged junction blob.

## 10. Order and simplify samples

Convert graph edge pixels into subpixel sample coordinates.

Possible refinements:

- Centre samples between opposing boundaries rather than retaining integer pixel centres.
- Smooth along arc length with an edge-preserving filter.
- Detect corners from curvature and source evidence.
- Remove redundant collinear samples.
- Preserve endpoints and junction attachment points.

The simplified samples are inputs to curve fitting, not final control points.

## 11. Fit Bézier curves

Fit cubic Bézier segments under an error tolerance expressed in source-image units.

The fitter should:

- Estimate endpoint tangents.
- Attempt one segment over the current sample range.
- Measure maximum and aggregate error.
- Reparameterise samples when useful.
- Split recursively at the worst error or a detected corner.
- Merge adjacent segments when the combined fit remains within tolerance.
- Fit closed loops without introducing a visible seam.

Error should consider more than point distance. A curve can be close to samples but still render poorly with the estimated stroke width. Later refinement should include rendered-edge distance.

## 12. Resolve endpoints and junctions

### Endpoints

An endpoint may require:

- Extension to the visual end of the source region.
- A round, square or butt cap.
- A tapered width profile.
- Snapping to a nearby endpoint when a gap is likely accidental.

### Junctions

Simple SVG strokes overlap at a shared junction, which is often visually correct. However, raster intersections may create bulges or ambiguous connectivity.

The pipeline should:

- Place incident path endpoints at one logical junction.
- Estimate each incident tangent outside the junction blob.
- Keep paths separate unless the evidence indicates one continuous stroke passing through.
- Optionally pair opposite edges by tangent continuity.
- Preserve branching topology even if the exact drawing order is unknown.

Drawing-order inference is a later feature and should not be required for faithful static output.

## 13. Trace filled shapes

Filled regions use contour tracing rather than skeletonisation.

Steps:

- Extract outer contours and holes.
- Determine nesting and winding.
- Convert pixel boundaries to subpixel coordinates.
- Detect corners.
- Fit Bézier curves under a contour-error tolerance.
- Remove tiny holes according to the noise setting.
- Validate self-intersections.
- Preserve disconnected islands as separate elements or a compound path.

Small solid regions must not be forced into strokes merely because their skeleton exists.

## 14. Assemble the hybrid document

Combine stroke and fill results into one document.

Assembly responsibilities:

- Assign stable IDs.
- Preserve region-to-element relationships.
- Set z-order using source overlap and classification rules.
- Group elements by source component or colour where useful.
- Deduplicate coincident geometry.
- Retain uncertainty metadata.

The internal model should preserve more information than the exported SVG so the user can revise classifications later.

## 15. Render back to raster

Render the vector document at the working resolution and compare it with the cleaned source.

Comparison outputs:

- Pixel difference.
- Foreground intersection-over-union.
- Distance between source and rendered edges.
- False-positive and false-negative regions.
- Topology differences.
- Per-element error contribution.

Render-back comparison serves three purposes:

1. Detect obviously bad results.
2. Guide automatic parameter refinement.
3. Explain errors to the user.

## 16. Refine

Refinement should optimise a constrained objective rather than blindly add more points.

Possible objective terms:

- Raster reconstruction error.
- Edge distance.
- Node count penalty.
- Curvature smoothness.
- Width variation penalty.
- Topology preservation.
- Deviation from user-locked geometry.

The initial implementation should use targeted deterministic adjustments:

- Move endpoints.
- Adjust a control handle.
- Split a high-error segment.
- Merge low-error adjacent segments.
- Re-estimate width.

A full differentiable renderer is optional research, not an MVP requirement.

## 17. Validate

Before exposing or exporting a result, validate:

- Finite coordinates.
- Valid path command order.
- No empty elements.
- Closed fills are actually closed.
- Winding and holes are consistent.
- Stroke widths are positive.
- Stable IDs are unique.
- Bounds are sane.
- Exported SVG renders without parser errors.

A failed region may fall back to an outline trace with a warning rather than invalidate the complete document.

## 18. Export

SVG output should use semantic elements:

```svg
<path d="..." fill="none" stroke="#111" stroke-width="5.8" stroke-linecap="round" stroke-linejoin="round"/>
<path d="..." fill="#111" fill-rule="evenodd"/>
```

Export options control:

- Precision.
- Grouping.
- IDs.
- Metadata.
- Relative or absolute commands.
- Compound paths.
- Stroke expansion only when explicitly selected.

## Difficult cases

### Low resolution

A four-pixel-wide raster stroke contains little reliable centreline or width information. Fekthor should warn, offer edge-preserving enlargement and show lower confidence.

### Variable-width brushes

Constant-width reconstruction will lose intent. These require width profiles, outline output or both.

### Touching parallel lines

Connected-component analysis may merge separate strokes. Separation can use local width, contour necks and user cuts.

### Filled object with an outline

Colour segmentation and nested-region analysis should preserve the fill and its surrounding stroke as separate elements when evidence supports it.

### Intersections

Static raster evidence may not reveal which stroke passes over another. Preserve visible geometry and topology without claiming a drawing order that cannot be inferred.

### Texture and shading

Texture should not become thousands of tiny paths by default. Classify it as Texture or Ignore, or offer a separate stylised tracing mode later.

## Determinism

Every stage must be deterministic for identical input, configuration and engine version. Parallel region processing must not change element ordering or floating-point results unpredictably. Stable sorting and explicit numeric tolerances are required.

## Diagnostics required from the first prototype

- Cleaned foreground mask.
- Connected-component image.
- Width/distance map.
- Skeleton image.
- Topology graph overlay.
- Fitted Bézier overlay.
- Rendered result.
- Difference image.
- Per-stage timing.
- Path and node counts.

Without these artefacts, algorithm failures will be difficult to diagnose and compare.

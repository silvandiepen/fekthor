# Research plan

## Objective

Determine which combination of deterministic algorithms produces the best editable centreline and hybrid vector output for Fekthor’s target images. Research must be fixture-driven and measurable. Existing projects may be used as behavioural baselines or dependency candidates only after technical and licence review.

## Questions to answer first

1. Which skeletonisation method best preserves endpoints, loops and junctions on antialiased line art?
2. How should junction-pixel clusters collapse into stable logical nodes?
3. Which width estimate is most stable near corners, caps and intersections?
4. Which Bézier-fitting method gives the best fidelity-to-node-count trade-off?
5. Which features reliably separate narrow strokes from small solid marks?
6. When should the engine fall back from centreline output to contour output?
7. How much render-back optimisation improves results beyond direct curve fitting?
8. Which existing libraries can be used safely in a distributable application?

## Baseline categories

### Conventional outline tracing

Use a mature outline tracer as a baseline for filled shapes and raster similarity. This demonstrates the structural problem Fekthor is intended to solve: a thick raster line commonly becomes a closed filled contour rather than a real stroke.

Measure:

- Visual similarity.
- Path count.
- Node count.
- SVG size.
- Percentage of line content represented as filled outlines.

### Existing centreline tracing

Evaluate centreline-capable tools on the same fixture set. Do not assume their output is directly suitable for production. Inspect:

- Topology preservation.
- Width recovery.
- Junction behaviour.
- Noise and spur behaviour.
- Bézier quality.
- Output semantics.
- Availability as a reusable library.
- Licence obligations.

### Shape and colour tracing

Evaluate a modern shape-focused tracer for filled and flat-colour regions. It may serve as a dependency, reference implementation or benchmark for the Shapes branch of the pipeline.

### Manual reference vectors

Prepare high-quality manual vectors for a smaller subset. These are not necessarily the only correct answers, but they provide a semantic reference for path structure, stroke/fill classification and node economy.

## Candidate algorithm families

## Foreground extraction

Evaluate:

- Global luminance thresholding.
- Histogram-based automatic thresholds.
- Adaptive/local thresholding.
- Background colour-distance segmentation.
- Alpha-driven segmentation.
- Small segmentation models for difficult scans, only after deterministic baselines.

Tests should include clean images, off-white backgrounds, uneven scans, shadows and JPEG ringing.

## Morphological cleanup

Evaluate conservative combinations of:

- Opening.
- Closing.
- Hole filling.
- Connected-component filtering.
- Gap linking based on endpoint direction.

Generic morphology can alter topology. Compare it against topology-aware gap repair that acts on likely endpoints instead of all pixels.

## Distance transform

Compare exact and approximate Euclidean distance transforms for:

- Width accuracy.
- Speed.
- Memory.
- Stability at diagonal boundaries.

The distance map is also useful for medial-axis extraction, local feature sizes and classification.

## Skeletonisation and medial axes

Evaluate at least:

- Iterative topology-preserving thinning.
- Medial-axis extraction from the distance transform.
- A hybrid that thins first and refines positions from opposing boundaries.

Desired behaviour:

- One stable centre branch for a constant-width stroke.
- Correct loop preservation.
- Minimal artificial spurs.
- Stable junction placement.
- Subpixel centre estimates.

Create fixtures where the correct topology is known exactly.

## Skeleton graph extraction

Research:

- 8-connected versus alternative neighbourhood treatment.
- Junction-cluster collapse.
- Loop anchoring.
- Edge ordering.
- Spur scoring.
- Pairing incident edges through a junction by tangent continuity.

Graph construction should be independently testable from skeletonisation.

## Stroke-width recovery

Compare:

- Twice the distance-transform value at the centreline.
- Opposing-boundary ray intersections along local normals.
- Robust aggregation across a graph edge.
- Joint estimation of path and width.

Evaluate separately at:

- Straight sections.
- Curves.
- Corners.
- Round and square caps.
- T-junctions.
- Crossings.

## Curve fitting

Candidate approaches:

- Recursive cubic Bézier fitting with chord-length parameterisation.
- Corner detection followed by per-span fitting.
- Polyline simplification before Bézier fitting.
- Curvature-aware fitting.
- Render-aware local optimisation after fitting.

Measure:

- Maximum sample distance.
- Rendered edge distance.
- Segment count.
- Node count.
- Curvature smoothness.
- Stability under one-pixel source perturbations.

## Contour tracing

The Shapes branch needs:

- Subpixel contour extraction.
- Hole and nesting preservation.
- Corner detection.
- Bézier simplification.
- Self-intersection detection.
- Compound-path generation.

Compare a custom minimal implementation against candidate reusable libraries. Prefer reuse when quality, licence and integration are suitable.

## Stroke/fill classification

Start with interpretable features:

- Area-to-perimeter ratio.
- Median and variance of local thickness.
- Skeleton-length-to-area ratio.
- Bounding-box elongation.
- Endpoint and junction count.
- Hole count.
- Complexity of centreline representation versus contour representation.
- Region size relative to global stroke-width distribution.

A useful heuristic may infer the dominant drawing stroke width globally and classify narrow regions relative to it. Small compact regions near that width remain ambiguous and require context.

Only train a model after collecting failure examples from deterministic rules.

## Render-back refinement

Begin with a simple CPU reference renderer. Test whether local optimisation can improve:

- Endpoint placement.
- Junction placement.
- Control handles.
- Stroke width.
- Segment split points.

Do not introduce a differentiable renderer until simple deterministic refinement is measured and found insufficient.

## Dependency evaluation template

For every candidate library or reference project, record:

- Project and repository.
- Purpose.
- Active maintenance status.
- Language and integration cost.
- Supported platforms.
- Output quality on Fekthor fixtures.
- Runtime and memory.
- Determinism.
- Licence and transitive dependencies.
- App Store or redistribution implications.
- Whether code is linked, executed as a process or used only as a benchmark.
- Decision: adopt, adapt, benchmark only or reject.

Licence information must be verified from the actual version and repository before adoption.

## Experiment format

Each experiment should be reproducible and stored as a short report:

```markdown
# Experiment: <name>

## Hypothesis

## Implementation or candidate

## Fixtures

## Configuration

## Results

## Metrics

## Visual observations

## Failure cases

## Licence/integration notes

## Decision
```

Store generated diagnostics as CI artefacts or in a dedicated research-output location rather than committing large binary sets indiscriminately.

## Initial experiments

### R-001 Skeleton comparison

Run two thinning approaches and one medial-axis approach on synthetic lines, loops, branches, crossings and noisy scans.

Decision criterion: topology first, then spur count, centre accuracy and speed.

### R-002 Junction collapse

Compare centroid, distance-weighted centre and fitted tangent-intersection positions for junction clusters.

Decision criterion: rendered intersection quality and stability.

### R-003 Width estimation

Compare median distance-transform width with normal-ray boundary width.

Decision criterion: error away from and near junctions, plus robustness to antialiasing.

### R-004 Bézier fitting

Compare direct recursive fitting with polyline simplification followed by fitting.

Decision criterion: edge error at a fixed node budget.

### R-005 Rule-based classification

Build a generated dataset of strokes and fills, then test interpretable features and confidence thresholds.

Decision criterion: classification accuracy and confident-error rate.

### R-006 Hybrid export

Produce a mixed SVG containing centreline strokes and filled shapes, then round-trip through independent renderers and vector editors.

Decision criterion: structural preservation and visual consistency.

### R-007 Incremental region recomputation

Change one region’s classification and verify unchanged elements retain IDs and byte-identical geometry.

Decision criterion: correctness and processing-time reduction.

## Research stop conditions

Research should lead to decisions, not an indefinite algorithm survey. A candidate is good enough to proceed when:

- It meets topology requirements on the accepted fixture subset.
- Its failures are visible and correctable.
- It can be implemented and distributed safely.
- Further alternatives show diminishing measurable benefit.

The product may retain algorithm interfaces so better implementations can be substituted later without delaying the native prototype indefinitely.

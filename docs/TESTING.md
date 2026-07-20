# Quality and testing

## Quality definition

A vector result is not good merely because it resembles the source at thumbnail size. Fekthor must test visual fidelity, topology, editability, complexity, determinism and export compatibility.

## Test layers

### Unit tests

Every geometry and image-processing module should have focused unit tests.

Examples:

- Thresholding and alpha handling.
- Connected-component labelling.
- Hole and nesting detection.
- Distance-transform values on known masks.
- Skeleton endpoint and junction detection.
- Graph construction for lines, loops, T-junctions and crossings.
- Spur pruning.
- Width estimation.
- Bézier evaluation and fitting.
- Curve splitting and merging.
- Path closure.
- Winding and fill rules.
- SVG serialisation and parsing.
- Cache-key and revision behaviour.

### Property tests

Geometry benefits from generated tests and invariants.

Examples:

- Fitted path coordinates are finite.
- Closed contours remain closed after simplification.
- Rendering a path after serialisation remains within tolerance of rendering before serialisation.
- Simplification never increases node count.
- Skeleton graph traversal accounts for all retained skeleton pixels.
- Region-local recomputation does not alter unrelated element geometry.
- Same input and settings produce byte-stable output when byte stability is expected.

### Fixture tests

Maintain a curated fixture set containing source images, metadata and expected structural properties.

Each fixture should define expectations such as:

- Number of connected components.
- Expected stroke and fill counts or ranges.
- Endpoint and junction topology.
- Maximum visual error.
- Maximum path and node count.
- Regions that must remain separate.
- Regions expected to be uncertain.

Avoid requiring exact control-point coordinates for every fixture because legitimate fitter improvements may change them. Use structural and rendered expectations where possible.

### Golden render tests

Render generated vectors at one or more fixed resolutions and compare them with accepted golden images.

Golden tests should report:

- Changed pixel count.
- Maximum and mean difference.
- Edge-distance change.
- Bounding box of the changed region.
- A visual diff artefact in CI.

Golden updates must be explicit and reviewed. Do not automatically replace expected images when tests fail.

### Export tests

For every supported export preset:

- Parse the generated SVG with an independent parser.
- Rasterise it with at least one independent renderer.
- Check for invalid numeric values.
- Verify viewBox and bounds.
- Verify strokes remain strokes in editable presets.
- Verify fills remain closed and preserve holes.
- Reopen exported files in integration fixtures where practical.

Manual compatibility passes should periodically test Safari, Chrome and at least two mainstream vector editors.

### UI tests

Native application tests should cover critical workflows:

- Open an image.
- Wait for a preview.
- Switch vectorisation mode.
- Correct a region classification.
- Undo and redo.
- Save and reopen a project.
- Export SVG.
- Cancel processing.
- Recover from a failed processing attempt.

UI tests should not duplicate engine quality tests.

## Benchmark dataset

The benchmark set should contain both synthetic and real examples.

### Categories

- Clean constant-width line art.
- Closed stroked loops.
- Mixed strokes and solid marks.
- T-junctions and multi-way branches.
- Crossings.
- Parallel close lines.
- Filled shapes with holes.
- Filled shapes with outlines.
- Low-resolution antialiased icons.
- JPEG-compressed screenshots.
- Scanned ink with paper shadow.
- Pencil lines.
- Signatures.
- Flat-colour illustrations.
- Difficult negative cases containing texture or shading.

### Dataset splits

- Development fixtures for rapid iteration.
- Regression fixtures committed to the repository where licensing permits.
- Private evaluation set not used to tune thresholds.
- Performance set containing large and pathological images.

Every non-synthetic fixture must include its origin and licence or permission status.

## Metrics

No single metric determines quality.

### Raster similarity

- Foreground intersection-over-union.
- Precision and recall of rendered foreground.
- Mean absolute pixel difference.
- Structural similarity where appropriate.

Raster similarity can reward overly complex paths, so it must be balanced by complexity metrics.

### Edge accuracy

- Symmetric Chamfer distance between source and rendered edges.
- Percentile edge distance, especially the 95th percentile.
- Maximum local deviation after excluding isolated noise.

### Topology

- Connected-component count.
- Hole count.
- Endpoint count.
- Junction degree distribution.
- Loop count.
- Region adjacency.

Topology errors should be treated as more serious than small local pixel differences.

### Editability

- Path count.
- Node count.
- Segments per path.
- Fraction of line-like content emitted as strokes rather than filled outlines.
- Number of self-intersections.
- Number of tiny elements below a useful size.
- SVG byte size.

### Classification

- Stroke/fill precision, recall and F1.
- Uncertain-region rate.
- Confident-error rate.
- Number of user corrections needed in evaluation sessions.

### Performance

- Time per stage.
- Total preview time.
- Final-processing time.
- Peak resident memory.
- Cache hit rate.
- Incremental recomputation time.
- Export time.

## Initial quality targets

Targets should be refined after the first benchmark baseline. Initial engineering targets:

- Clean 2048 × 2048 monochrome preview in under 3 seconds on the reference development Mac.
- Final result in under 10 seconds for the same class of image.
- No topology regression on accepted clean-line fixtures.
- At least 90% foreground intersection-over-union on clean synthetic fixtures while remaining within the fixture node budget.
- Smart classification above 95% on synthetic constant-width stroke versus solid-fill regions.
- Byte-deterministic SVG for identical input, settings and engine version.
- No unrelated element changes after a region-local classification override.

These are development targets, not marketing claims. Real-world thresholds should be based on measured data.

## Baseline comparisons

The research phase should compare Fekthor against representative existing approaches:

- Conventional outline tracing.
- Existing centreline tracing.
- Shape-focused colour tracing.
- A manually prepared reference vector for selected fixtures.

Compare both visual output and structure. A conventional tracer may achieve excellent pixel similarity but still fail the product goal by returning doubled filled contours.

## Manual review rubric

Reviewers score each result from 1 to 5 on:

- Visual fidelity.
- Correct stroke/fill semantics.
- Topology.
- Smoothness.
- Preservation of intentional irregularity.
- Node economy.
- Ease of correction.
- Export usefulness.

The review UI should randomise method labels when comparing algorithms to reduce bias.

## Regression policy

A change may improve average similarity while breaking important topology. Therefore:

- Topology regressions block merging unless explicitly accepted.
- Large fixture-specific visual regressions require explanation.
- Node-count increases require a measured fidelity benefit.
- Performance regressions above a defined tolerance require profiling evidence.
- Golden changes must include generated diff artefacts.

## Fuzzing and robustness

Fuzz inputs should include:

- Empty images.
- Fully filled images.
- One-pixel dimensions.
- Very large dimensions with allocation guards.
- Corrupt metadata.
- Extreme alpha values.
- Checkerboards and high-frequency noise.
- Thousands of tiny components.
- Deeply nested holes.
- Self-touching contours.

The engine must fail with structured errors rather than panic or allocate without bounds.

## Performance benchmarking

Benchmark each major stage independently and end to end. Store benchmark metadata:

- Commit SHA.
- Machine identifier.
- OS and compiler versions.
- Input hash.
- Configuration.
- Warm or cold cache.

Use release builds and fixed thread counts for comparable results.

## CI strategy

On each pull request:

- Format and lint.
- Unit and property tests.
- Small fixture and SVG validation suite.
- Determinism checks.

On main or scheduled runs:

- Complete golden suite.
- Large performance fixtures.
- macOS app build and integration tests.
- Cross-renderer SVG checks.
- Dependency and licence checks.

CI should upload diff images, diagnostics and benchmark summaries for failures.

## Test fixture layout

```text
fixtures/
├── inputs/
│   ├── line-art/
│   ├── mixed/
│   ├── fills/
│   ├── scans/
│   └── pathological/
├── metadata/
│   └── <fixture>.json
├── expected/
│   ├── renders/
│   ├── structure/
│   └── diagnostics/
└── licences/
```

## Release checklist

Before a public release:

- Complete regression suite passes.
- Export compatibility pass completed.
- Project migration tested from every previously released format version.
- Crash and cancellation paths tested on large images.
- Accessibility audit completed for the primary workflow.
- Model-free operation verified on a clean machine.
- Network-disabled import, process, save and export verified.
- Third-party licences reviewed.
- Example and marketing images have documented usage rights.

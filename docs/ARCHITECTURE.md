# Technical architecture

## Goals

The architecture must support a native macOS application today and a reusable vectorisation engine later. The engine should be deterministic, testable without UI, capable of incremental recomputation and independent of Apple-only rendering APIs.

## Proposed stack

### Application

- Swift and SwiftUI.
- AppKit integration where SwiftUI does not provide sufficient document, canvas or pointer behaviour.
- Core Graphics for native vector preview and PDF output.
- Core Image or Accelerate for selected image operations where it materially improves performance.
- Core ML only for optional on-device models.

### Vectorisation core

- Rust library with no UI dependencies.
- Narrow C-compatible interface or generated bindings through UniFFI after a small proof of concept.
- CPU implementation first.
- Optional Metal acceleration only after profiling identifies worthwhile stages.
- Command-line executable using the same library for tests and batch processing.

Rust is selected because the geometry pipeline needs predictable performance, memory safety, reusable modules and portability beyond macOS. The native interface should pass owned buffers and serialisable result structures rather than exposing internal pointers throughout the Swift application.

## High-level components

```text
FekthorApp
├── Document UI
├── Canvas and interaction
├── Inspector and commands
├── Project persistence
├── Export orchestration
└── FekthorBridge
    └── fekthor-core
        ├── image
        ├── preprocess
        ├── segmentation
        ├── classify
        ├── skeleton
        ├── topology
        ├── stroke
        ├── contour
        ├── bezier
        ├── optimize
        ├── render
        ├── compare
        ├── document
        ├── export-svg
        └── diagnostics
```

## Core pipeline contracts

Each stage should accept an immutable input and produce a versioned output. Intermediate artefacts should be cacheable and serialisable when useful.

### Image input

Normalised image data:

- Width and height.
- Pixel format.
- Premultiplied or straight alpha state.
- Colour space metadata.
- Orientation already applied.
- Source transform.

### Preprocessed image

- Linear or perceptually appropriate luminance buffer.
- Optional clustered colour buffer.
- Foreground probability or binary mask.
- Cleanup mask changes.
- Background estimate.
- Parameters and pipeline version.

### Region map

- Connected component IDs.
- Bounding boxes.
- Pixel area.
- Contours and holes.
- Local width statistics.
- Classification features.
- Adjacency relationships.

### Classification result

For every region:

- Stroke, Fill, Texture, Ignore or Uncertain.
- Confidence.
- Automatic explanation values, such as width consistency and compactness.
- User override.

### Vector document

- Artboard.
- Layers and groups.
- Stroke paths.
- Filled shapes.
- Source-region references.
- Confidence and diagnostic metadata.
- Stable element IDs.

## Module responsibilities

### `image`

Decodes engine-neutral image buffers supplied by the host, validates dimensions and performs colour-space normalisation. Platform decoding remains in Swift for the first application, while the CLI may use a Rust decoder.

### `preprocess`

Performs grayscale conversion, background estimation, thresholding, denoising, morphological cleanup, colour clustering and user cleanup-mask application.

Every operation should record its parameters. Preview and final processing use the same operations at different resolutions.

### `segmentation`

Builds connected components and region relationships. It should support splitting and merging regions without discarding the complete document cache.

### `classify`

Uses geometric rules first and an optional model later. Inputs may include region area, perimeter, compactness, local thickness, width variance, skeleton-to-area ratio, hole count, edge proximity and colour information.

The rule-based classifier must remain available when no model is installed.

### `skeleton`

Produces a one-pixel-wide topology-preserving representation for stroke regions. Different algorithms may be implemented behind a shared interface and benchmarked.

### `topology`

Converts skeleton pixels into a graph:

- Nodes for endpoints, junctions and loop anchors.
- Edges for ordered pixel chains.
- Connectivity and component IDs.
- Junction neighbourhoods.

It also handles spur pruning, short-edge merging and stable graph traversal.

### `stroke`

Estimates stroke widths, reconstructs centreline paths, resolves endpoints and junctions, and creates semantic stroke elements.

### `contour`

Traces filled regions, holes and nested shapes. It must preserve winding rules and avoid self-intersections.

### `bezier`

Fits line, quadratic or cubic segments to ordered samples under an error bound. Cubic Bézier output is the standard representation for SVG compatibility.

The module should support:

- Corner detection.
- Smooth tangent estimation.
- Recursive splitting.
- Closed-loop fitting.
- Error measurement in source coordinates.
- Segment refitting after local edits.

### `optimize`

Reduces unnecessary nodes, merges compatible segments, normalises precision and performs render-aware refinement. Optimisation must preserve topology and remain deterministic.

### `render`

Provides an engine-neutral raster renderer for tests and comparison. The shipping app may use Core Graphics for display, but tests need a consistent reference renderer.

### `compare`

Computes raster and edge-based differences between the source mask and rendered vectors. It reports both global metrics and local error regions.

### `document`

Defines the internal vector document, commands and serialisation structures. The UI should not maintain a separate incompatible geometry model.

### `export-svg`

Converts the document to standards-based SVG with configurable structure and precision. Output should preserve strokes unless the selected export preset explicitly expands them.

### `diagnostics`

Produces intermediate images, graph dumps, timings, warnings and per-stage metrics. Diagnostics are essential during research but must be removable from production exports.

## Application architecture

### Document model

Use a document-based application. A `FekthorDocument` owns:

- Original image reference or embedded source.
- Processing configuration.
- Core vector document snapshot.
- User cleanup mask.
- User classification overrides.
- Manual vector edits.
- Cache manifest.
- Export presets.

The document issues commands through an undo manager. A command should describe intent, such as `SetRegionClassification`, rather than replacing the entire vector document blindly.

### Processing coordinator

A dedicated actor coordinates engine work:

- Cancels obsolete preview jobs.
- Debounces slider changes.
- Chooses preview or final resolution.
- Reuses cached stages.
- Publishes progress.
- Applies results only when their input revision still matches the document.

No engine work should block the main actor.

### Canvas

The canvas should use a retained scene model with separate source, vector, selection and diagnostic layers. It must support large images without creating a SwiftUI view for every path node.

A custom AppKit-backed canvas or Metal-backed renderer may be needed if Core Graphics display performance becomes insufficient. Start with the simplest implementation and profile before adding GPU complexity.

## Incremental recomputation

Settings affect different stages. The cache graph should invalidate only what is necessary.

Examples:

- Changing overlay opacity invalidates no engine stages.
- Changing Bézier detail reruns fitting, optimisation, render and comparison.
- Changing noise removal reruns preprocessing and every dependent stage.
- Overriding one region from Fill to Stroke reruns classification-dependent stages for that region and document assembly.
- Moving a Bézier node invalidates only rendering, comparison and export for the edited element.

Every cached artefact should include:

- Source revision.
- Stage version.
- Parameter hash.
- Region revision where applicable.
- Resolution scale.

## Native bridge

The initial bridge should expose coarse operations rather than every internal class:

```text
create_session(image, configuration) -> session_id
process(session_id, target_stage, changed_regions) -> result
apply_cleanup_mask(session_id, mask_delta) -> revision
set_region_override(session_id, region_id, classification) -> result
edit_vector(session_id, command) -> result
export_svg(session_id, options) -> bytes
get_diagnostics(session_id, request) -> diagnostic_payload
cancel(job_id)
```

Data crossing the boundary should use stable DTOs. Large pixel buffers should avoid repeated copies where the chosen bridge permits safe shared memory.

## Persistence

A `.fekthor` document should be a package containing versioned files:

```text
project.fekthor/
├── manifest.json
├── source/
│   └── original.<ext>
├── document.json
├── settings.json
├── masks/
│   ├── cleanup.bin
│   └── regions.bin
├── cache/
│   └── ...
└── preview.png
```

Caches are disposable. The project must remain recoverable from the source, settings, overrides and manual edit operations even when cached data is removed.

## Error model

Core errors should be structured and recoverable:

- Invalid image.
- Unsupported dimensions or allocation failure.
- Empty foreground.
- Topology construction failure.
- Curve fitting failure for a region.
- Export incompatibility.
- Cancelled operation.
- Internal invariant violation.

A region-level error should not normally fail the complete document. The engine may return a partial result with warnings and a fallback contour for the failed region.

## Performance strategy

1. Build a correct scalar CPU pipeline.
2. Add stage timings and memory measurements.
3. Parallelise independent connected regions.
4. Reuse image pyramids and distance transforms.
5. Reduce bridge copies.
6. Use SIMD or Accelerate where it simplifies hot loops.
7. Consider Metal only for proven bottlenecks such as large distance transforms or repeated raster comparison.

## Repository structure

Suggested initial layout:

```text
fekthor/
├── README.md
├── AGENTS.md
├── docs/
├── apps/
│   └── macos/
├── crates/
│   ├── fekthor-core/
│   ├── fekthor-cli/
│   ├── fekthor-svg/
│   └── fekthor-testkit/
├── fixtures/
│   ├── inputs/
│   ├── expected/
│   └── metadata/
├── scripts/
└── .github/workflows/
```

## CI

CI should run:

- Rust formatting, linting and tests on Linux.
- Core golden-image tests with deterministic fixtures.
- Swift formatting or lint checks.
- macOS application build on changes affecting the app or bridge.
- SVG validation.
- Licence and dependency review checks where feasible.

macOS CI is comparatively expensive, so engine tests should remain runnable on Linux and only native integration tests should require macOS.

## Observability during development

Development builds should expose a diagnostics workspace showing:

- Every intermediate mask.
- Connected components.
- Skeleton graph.
- Width map.
- Fitted samples and control points.
- Difference image.
- Stage timings.
- Cache hits and invalidations.

This view is a development instrument, not part of the normal user interface.

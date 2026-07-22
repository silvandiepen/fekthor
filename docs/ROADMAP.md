# Roadmap

> **2026-07-22 — editor pivot.** With the tracing engine proven (quality plans
> 01–07 complete), Fekthor pivots to an **editor-first** product: a vector
> editor whose flagship use case is icon-set/workspace management, with
> tracing as one big feature. The active roadmap is now
> [`plans/08-editor-p0.md`](plans/08-editor-p0.md) (P0 foundation → P1
> workspace → P2 export profiles + containers → P3 tokens → P4 editor core →
> P5 pen/booleans → P6 interchange). The phases below are the original
> tracing-first roadmap, kept for the engine milestones that remain relevant.

The roadmap is quality-first. Fekthor should not begin with a polished application shell around an unproven tracing engine. The first milestone is a measurable centreline-vectorisation prototype with diagnostics and fixtures.

## Phase 0 — Repository and research foundation

### Deliverables

- Rust workspace with `fekthor-core`, `fekthor-cli` and `fekthor-testkit` crates.
- Initial fixture format and synthetic fixture generator.
- Command-line command that accepts an image and writes diagnostics.
- Benchmark harness with per-stage timing.
- Licence review record for evaluated dependencies.
- CI for formatting, linting and engine tests.

### Exit criteria

- The core builds and tests on macOS and Linux.
- A fixture can produce cleaned mask, skeleton and diagnostic images.
- Results are deterministic across repeated runs on the same platform.
- Architecture and document-model assumptions have small executable proofs.

## Phase 1 — Centreline research spike

### Goals

Prove that clean line art can become real stroked paths with acceptable topology and node count.

### Work

- Implement image normalisation and binary foreground masks.
- Implement connected components.
- Evaluate at least two skeletonisation approaches.
- Build endpoint, junction and loop graph extraction.
- Compute distance transform and constant-width estimates.
- Implement chain cleanup and spur pruning.
- Implement cubic Bézier fitting.
- Emit diagnostic SVG strokes.
- Render generated SVG and calculate comparison metrics.
- Create synthetic line, loop, T-junction, crossing and branch fixtures.

### Exit criteria

- Clean constant-width fixtures produce actual stroked SVG paths.
- Endpoints, loops and branch topology are preserved on accepted fixtures.
- Generated node count is materially lower than outline tracing.
- Diagnostic output makes failures explainable.
- The team can identify which skeleton and fitting approaches to carry forward.

## Phase 2 — Filled shapes and Smart mode

### Goals

Support mixed artwork rather than only pure strokes.

### Work

- Implement contour tracing with holes.
- Fit and simplify filled contours.
- Implement deterministic stroke/fill feature extraction.
- Implement initial rule-based classifier and confidence.
- Combine strokes and fills into the internal document model.
- Add local user overrides to CLI configuration.
- Add hybrid SVG export.
- Build mixed fixtures: pupils, silhouettes, outlined fills and small solid marks.

### Exit criteria

- One source image can produce both stroked paths and filled shapes.
- User overrides can change one region without altering unrelated geometry.
- Exported SVG renders consistently in independent renderers.
- Smart classification reaches the initial synthetic benchmark target.

## Phase 3 — Native macOS prototype

### Goals

Validate the complete import, inspect, correct and export workflow.

### Work

- Create SwiftUI document application.
- Build the Rust-to-Swift bridge.
- Add open, drop and clipboard import.
- Implement source, vector, split and overlay views.
- Add Smart, Strokes and Shapes controls.
- Add progress, cancellation and preview-quality processing.
- Show regions and confidence.
- Allow Stroke, Fill, Ignore and Automatic overrides.
- Export SVG.
- Save a minimal `.fekthor` project.

### Exit criteria

- A non-technical user can import the reference illustration, correct a wrong region and export useful SVG.
- Processing does not block the interface.
- Project save and reopen preserve the result and overrides.
- Core workflow functions without network access.

## Phase 4 — MVP editing and comparison

### Goals

Make results correctable without leaving the application.

### Work

- Implement Difference view.
- Add node editing for selected paths.
- Add join, break, open, close and simplify operations.
- Add region cut and merge.
- Add cleanup-mask erase and restore tools.
- Add stroke style controls.
- Add fill colour controls.
- Implement complete undo and redo.
- Add PDF export and SVG presets.
- Add structural result summary.

### Exit criteria

- All MVP acceptance criteria in `FEATURES.md` pass.
- Manual corrections persist after save and reopen.
- Failed recomputation preserves the previous valid result.
- Accessibility review covers the complete primary workflow.

## Phase 5 — Reliability and first public release

### Goals

Turn the prototype into a dependable macOS product.

### Work

- Expand real-world fixture coverage.
- Tune preprocessing presets.
- Add local adaptive thresholding and scan cleanup.
- Improve error messages and partial-result fallbacks.
- Optimise incremental recomputation.
- Add export compatibility tests.
- Add autosave and recovery.
- Add onboarding help and example projects.
- Complete dependency and licence review.
- Package, sign, notarise and prepare distribution.

### Exit criteria

- Regression and compatibility suites pass.
- Clean 2048 × 2048 examples meet preview and final-processing targets on the reference Mac.
- Crash, cancellation and corrupted-project recovery have been tested.
- App works fully offline on a clean machine.
- Documentation and privacy disclosures match actual behaviour.

## Phase 6 — Version 1 improvements

### Candidate workstreams

- Variable-width strokes and tapered endpoints.
- Better junction reconstruction.
- Flat-colour clustering.
- Batch processing.
- Preset management.
- Command-line release.
- Advanced local smoothing and width tools.
- Layers, grouping, alignment and snapping.
- Additional export formats.
- Performance work based on profiling.

Workstreams should be prioritised from user-observed failures rather than implemented as one large release.

## Phase 7 — Optional ML assistance

### Prerequisites

- Deterministic baseline is stable.
- Real classification and correction data identifies measurable failure modes.
- Model evaluation and privacy requirements are defined.

### Work

- Build synthetic semantic-vector dataset.
- Train and evaluate compact region classifier.
- Compare against deterministic rules.
- Add calibrated uncertainty.
- Package optional on-device model.
- Explore endpoint continuation suggestions.
- Prototype Clean redraw as a separate workflow.

### Exit criteria

- Model reduces manual corrections on the private evaluation set.
- Confident-error rate is within an accepted threshold.
- App still operates completely without the model.
- No user image leaves the device during ordinary Smart vectorisation.

## Suggested implementation epics

### Epic A — Image and preprocessing

- Pixel-buffer model.
- Colour and alpha normalisation.
- Thresholding.
- Background estimation.
- Morphological cleanup.
- Cleanup-mask edits.

### Epic B — Region analysis

- Connected components.
- Contours and holes.
- Region features.
- Stable IDs.
- Split and merge.

### Epic C — Centreline engine

- Skeletonisation.
- Distance transform.
- Topology graph.
- Spur pruning.
- Width estimation.
- Endpoint and junction handling.

### Epic D — Geometry

- Sample simplification.
- Bézier fitting.
- Closed-loop fitting.
- Curve optimisation.
- Geometry validation.

### Epic E — Hybrid classification

- Rule-based classification.
- Confidence.
- User overrides.
- Document assembly.

### Epic F — Rendering and comparison

- Reference raster renderer.
- Difference metrics.
- Diagnostic images.
- Quality report.

### Epic G — Native application

- Document lifecycle.
- Canvas.
- Inspector.
- Processing coordinator.
- Undoable commands.
- Accessibility.

### Epic H — Persistence and export

- `.fekthor` package.
- SVG exporter.
- PDF exporter.
- Clipboard.
- Migration.

## First implementation backlog

The first coding cycle should contain only the following:

1. Initialise Rust workspace and CI.
2. Define engine image buffer and diagnostic-output interfaces.
3. Add synthetic constant-width stroke fixture generator.
4. Implement foreground mask for clean monochrome images.
5. Implement one skeletonisation algorithm.
6. Convert a simple skeleton line and loop into ordered graph edges.
7. Fit and export a cubic SVG stroke.
8. Render it back and produce a diff image.
9. Record timing, path count and node count.
10. Add regression fixtures before expanding the algorithm.

Do not begin AI integration or extensive application UI until this sequence proves the core premise.

## Prioritisation rule

When choosing between features, prefer the work that most improves one of these outcomes:

1. Correct stroke/fill semantics.
2. Correct topology.
3. Faster correction of ambiguity.
4. Lower vector complexity.
5. Better visual fidelity.
6. Better processing performance.

Additional formats and platform expansion come after the core result is consistently useful.

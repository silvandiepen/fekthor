# Architecture and product decisions

This file records the initial decisions that define Fekthor. They may be revised through explicit architecture decision records when implementation evidence changes.

## D-001 — Faithful vectorisation is separate from generative redraw

**Status:** Accepted

The normal vectorisation pipeline must reconstruct source geometry without intentionally redesigning it. Generative cleanup or redraw is a separate named mode with before/after comparison.

**Reasoning:** Users need to know whether the result is a conversion or a reinterpretation. Combining both behaviours would make fidelity unpredictable and difficult to test.

## D-002 — Hybrid stroke and fill output

**Status:** Accepted

Fekthor will not force every dark region into one representation. Stroke-like content becomes real stroked paths; genuinely solid content becomes filled shapes.

**Reasoning:** Pure outline tracing produces structurally poor line art, while pure centreline tracing misrepresents solid marks and silhouettes.

## D-003 — Native macOS application first

**Status:** Accepted

The initial product is a native macOS document application using SwiftUI with AppKit where required.

**Reasoning:** The intended workflow benefits from native file handling, clipboard formats, PDF support, pointer interaction and offline distribution. Starting with one platform reduces scope while the engine is still being proven.

## D-004 — Reusable Rust vectorisation core

**Status:** Accepted

Image analysis, topology, fitting, document geometry, diagnostics and SVG export belong in a reusable Rust core.

**Reasoning:** The engine requires predictable performance, memory safety, extensive testing and potential reuse by a CLI, other platforms or WebAssembly. UI-specific code should not own core geometry.

## D-005 — Deterministic engine before machine learning

**Status:** Accepted

The MVP uses deterministic image processing and geometry. ML may later assist classification and repair but remains optional.

**Reasoning:** Determinism enables reproducible testing, offline operation and understandable failure modes. ML should address measured gaps rather than substitute for an unproven core.

## D-006 — Offline-first and no account

**Status:** Accepted

Import, processing, editing, project saving and export work without a network connection or account.

**Reasoning:** Source images may be private, and ordinary vectorisation should not create recurring infrastructure cost or privacy uncertainty.

## D-007 — Project format is richer than SVG

**Status:** Accepted

Fekthor uses a native `.fekthor` package containing source, settings, classifications, edits and vector geometry. SVG is an export format.

**Reasoning:** SVG cannot reliably represent all raster evidence, uncertainty, recomputation state and non-destructive edits required by the product.

## D-008 — Real strokes remain strokes by default

**Status:** Accepted

Editable SVG export preserves `stroke`, `stroke-width`, caps and joins. Stroke expansion is an explicit export option.

**Reasoning:** Preserving stroke semantics is a central product promise. Expanding every stroke would recreate the problem Fekthor is intended to solve.

## D-009 — Quality is multi-dimensional

**Status:** Accepted

The project evaluates raster fidelity, edge distance, topology, classification, path complexity, determinism and performance.

**Reasoning:** Pixel similarity alone can reward a huge number of filled contour nodes and still produce unusable vectors.

## D-010 — Research spike before production UI

**Status:** Accepted

Implementation begins with a CLI, fixtures and diagnostics for centreline extraction before a substantial macOS interface is built.

**Reasoning:** The engine is the primary product risk. A polished interface cannot compensate for incorrect topology or doubled outlines.

## D-011 — Incremental recomputation is an architectural requirement

**Status:** Accepted

Pipeline stages are cacheable and revisioned. Local classification or geometry changes should not restart unrelated work.

**Reasoning:** Fast correction is essential to the workflow, and full reprocessing risks changing already accepted geometry.

## D-012 — Ambiguity remains visible

**Status:** Accepted

The classifier may return Uncertain with confidence and alternative interpretation data. The UI surfaces these regions.

**Reasoning:** Hiding uncertainty creates confident structural errors. A quick local correction is preferable to pretending every image has one obvious interpretation.

## D-013 — Region-level failure should produce partial results

**Status:** Accepted

A failed region may fall back to contour tracing or remain marked for review while other regions succeed.

**Reasoning:** One difficult detail should not discard a valid document result.

## D-014 — Constant-width strokes for MVP

**Status:** Accepted

The MVP estimates one robust width per stroke path or logical edge. Variable-width profiles follow later.

**Reasoning:** Constant-width output covers clean line art, is broadly editable and reduces the initial research surface. The internal model should remain extensible for later width profiles.

## D-015 — Core tests must run without macOS

**Status:** Accepted

Most engine tests, fixtures and SVG validation run on Linux as well as macOS. Native integration tests remain macOS-specific.

**Reasoning:** This improves iteration speed, reduces CI cost and enforces separation between the engine and the application.

## D-016 — No dependency adoption without licence review

**Status:** Accepted

Existing tracers and geometry libraries may be benchmarked freely, but code is not linked or copied into the product until its exact version, licence and transitive obligations are reviewed.

**Reasoning:** Vectorisation tools frequently use licences that may affect closed-source distribution or App Store packaging.

## D-017 — Low node count is an explicit optimisation objective

**Status:** Accepted

Curve refinement balances rendered error against path and node complexity.

**Reasoning:** A nearly perfect raster match with thousands of control points is difficult to edit, animate and maintain.

## D-018 — Manual editing is secondary to interpretation correction

**Status:** Accepted

The product provides node editing, but prioritises region reclassification, cuts, joins and cleanup-mask tools.

**Reasoning:** Correcting the inferred source structure is usually faster and produces more coherent vectors than manually repairing every control point.

## D-019 — Source image is retained non-destructively

**Status:** Accepted

Preprocessing creates masks and derived images rather than altering the original source asset.

**Reasoning:** Users need comparison, reset and future reprocessing with improved algorithms.

## D-020 — Stable IDs across local recomputation

**Status:** Accepted

Unchanged regions and elements retain stable IDs where possible.

**Reasoning:** Stable IDs support selection, undo, incremental export, regression testing and user confidence that a local change did not rewrite the complete document.

## Open decisions

The following require prototypes or product evidence:

### O-001 — Native bridge technology

Compare a minimal C ABI against generated UniFFI bindings for ownership clarity, performance and Swift ergonomics.

### O-002 — Skeletonisation algorithm

Select after the Phase 1 fixture comparison. The architecture must permit replacement.

### O-003 — Reference raster renderer

Choose a deterministic engine-neutral renderer for tests. The macOS display renderer may remain Core Graphics.

### O-004 — Initial distribution model

Decide between Mac App Store, direct distribution or both after sandbox, update and dependency requirements are known.

### O-005 — Project source embedding

Embedding is the default proposal. Test package size and linked-source requirements with large images before finalising.

### O-006 — Colour tracing implementation

Decide whether to implement contour tracing internally or adopt a suitable library after quality and licence evaluation.

### O-007 — Variable-width representation

Evaluate SVG-compatible profiles, expanded outlines and internal centreline-plus-profile representation before Version 1 work begins.

### O-008 — Licensing of Fekthor itself

No repository licence is selected. Choose it before accepting external contributions or publishing distributable source packages.

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

## D-004 — Reusable Swift vectorisation engine

**Status:** Revised 2026-07-20 (supersedes the original Rust-core decision)

Image analysis, topology, fitting, document geometry, diagnostics and SVG export belong in a reusable, UI-free **Swift** package (`swift/FekthorKit`), shared by the native apps and a headless CLI target.

**Reasoning:** Fekthor is a native macOS product built in the same Swift/monorepo style as the owner's other apps (GitKit/GitFolder). A single Swift toolchain removes the Rust↔Swift bridge (previously open decision O-001), lets the engine use native frameworks — Vision for contour tracing, CoreGraphics for rasterisation and render-back, Accelerate where profiling warrants — and keeps the whole codebase in one language and one repository. The engine remains deterministic, testable without UI, and independent of the app layer.

**Original decision (superseded):** A reusable Rust core exposed to Swift through UniFFI/C-ABI. Dropped because the product is macOS-native and the bridge added cost without a cross-platform requirement. O-001 (native bridge technology) is therefore closed as not applicable.

## D-005 — Deterministic engine before machine learning

**Status:** Accepted

The MVP uses deterministic image processing and geometry. ML may later assist classification and repair but remains optional.

**Reasoning:** Determinism enables reproducible testing, offline operation and understandable failure modes. ML should address measured gaps rather than substitute for an unproven core.

## D-006 — Offline-first and no account

**Status:** Accepted

Import, processing, editing, project saving and export work without a network connection or account.

**Reasoning:** Source images may be private, and ordinary vectorisation should not create recurring infrastructure cost or privacy uncertainty.

## D-007 — Project format is richer than SVG

**Status:** Revised 2026-07-22 by D-022 (editor pivot)

Fekthor uses a native `.fekthor` file for what SVG cannot hold. Since the editor pivot, plain `.svg` files are first-class documents (opened and saved in place), and `.fekthor` is a Codable-JSON **workfile** for workspace configuration; see D-022.

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

## D-015 — Engine is testable headlessly without the app

**Status:** Revised 2026-07-20 (the engine now depends on macOS frameworks)

The `FekthorKit` engine is UI-free and exercised headlessly via `swift test` and the `fekthor` CLI target, separately from the SwiftUI app. It depends on macOS frameworks (Vision, CoreGraphics), so tests run on macOS rather than Linux.

**Reasoning:** Keeping the engine independent of the app layer preserves fast iteration and clear separation. The original Linux-portability goal no longer applies now that the engine is native Swift using Apple frameworks; CI runs on macOS runners.

## D-016 — No dependency adoption without licence review

**Status:** Accepted

Existing tracers and geometry libraries may be benchmarked freely, but code is not linked or copied into the product until its exact version, licence and transitive obligations are reviewed.

**Reasoning:** Vectorisation tools frequently use licences that may affect closed-source distribution or App Store packaging.

## D-017 — Low node count is an explicit optimisation objective

**Status:** Accepted

Curve refinement balances rendered error against path and node complexity.

**Reasoning:** A nearly perfect raster match with thousands of control points is difficult to edit, animate and maintain.

## D-018 — Manual editing is secondary to interpretation correction

**Status:** Revised 2026-07-22 by D-021 (editor pivot): manual vector editing is now a primary product capability; interpretation correction remains the priority inside the trace feature.

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

## D-021 — Editor-first product (the editor pivot)

**Status:** Accepted 2026-07-22

Fekthor is a vector editor — "Illustrator basics, but better" — whose flagship use case is icon-set/workspace management. Raster tracing remains one big feature, not the product definition. Sequencing is workspace-first: P0 foundation → P1 workspace → P2 export profiles + containers → P3 tokens → P4 editor core → P5 pen/booleans → P6 interchange (`docs/plans/08-editor-p0.md`). The owner's **open-icon** set is the explicit acceptance yardstick. On-device AI icon generation is logged as far-future, after workspace + editor.

**Reasoning:** The proven engine (plans 01–07) plus editing toolkit already form most of an editor; the highest-value real workflow is managing an existing icon set, which exercises exactly the clean-SVG/round-trip strengths the engine has.

## D-022 — File formats: clean `.svg` + `.fekthor` JSON workfile, normalise-on-first-save

**Status:** Accepted 2026-07-22 (revises D-007)

Plain `.svg` holds geometry and is always written clean: a lone SVG opens and saves in place. The `.fekthor` file is a Codable-JSON workfile holding workspace configuration (folder reference, categories, artboard metadata, export profiles, style tokens, container slots) and may embed artboards as SVG text for self-contained documents. Save contract: **normalise on first save** (semantic equality with the source, idempotent thereafter — `write(read(write(read(f)))) == write(read(f))`), and Fekthor only ever writes files the user actually edited.

**Reasoning:** Icon workspaces are folders of SVGs owned by other tools too; a database format would hold them hostage. Idempotent, semantically-equal saves keep diffs reviewable and make the editor trustworthy on a real repository.

## D-023 — Style tokens bind by colour-slot matching; containers are slot rects

**Status:** Accepted 2026-07-22

Workspace style tokens bind to geometry by **colour-slot matching** (e.g. outline = `#010101`, accent = `#ed2024`), not by path ids. A container is a normal SVG in the workspace plus a slot rect (position + fit rule) stored in the workfile; content icons declare container memberships and export composes the matrix (`{icon}-{container}.svg`).

**Reasoning:** Colour slots survive editing, renaming and regeneration where path ids do not, and they match how the open-icon corpus already encodes semantics. Slot-rect containers reuse plain SVG for the container art, keeping the workfile small and the format inspectable.

## Open decisions

The following require prototypes or product evidence:

### O-001 — Native bridge technology — **Closed 2026-07-20**

Not applicable: the engine is native Swift (`FekthorKit`), so there is no Rust↔Swift bridge to design. See revised D-004.

### O-002 — Skeletonisation algorithm

Select after the Phase 1 fixture comparison. The architecture must permit replacement. Current Strokes-mode work uses Zhang-Suen thinning; a medial-axis alternative may be evaluated behind the same interface.

### O-003 — Reference raster renderer — **Closed 2026-07-20**

Resolved: CoreGraphics is the render-back reference renderer (`Rasterizer`), and Vision provides contour tracing. Both are deterministic on macOS and used for the render-back comparison harness.

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

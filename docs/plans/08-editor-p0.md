# Plan 08 — Editor pivot, P0 foundation

Fekthor pivots from a tracing app into a **vector editor** whose flagship use
case is icon-set/workspace management; tracing stays as one big feature. The
north-star acceptance target is the owner's real icon set **open-icon**
(`~/Repositories/_projects/open-icon`): ~1,120 raw SVGs in category folders
(`src/icons/<category>/`), inline-styled, stroke-based, hard-coded `#010101`
outline / `#ed2024` accent, per-icon JSON metadata, and an existing build
pipeline producing 1,829 CSS-variable-themed icons with -s/-m/-l/-xl stroke
variants. Fekthor should eventually manage that set and replace that build.

## Locked decisions (2026-07-22)

- Product: editor-first; "Illustrator basics, but better"; trace = one feature.
- Formats: plain `.svg` holds geometry, always written clean (lone SVGs open +
  save in place). `.fekthor` Codable-JSON workfile holds workspace config
  (folder ref, categories, artboard meta, export profiles, tokens, container
  slots) and may embed artboards for self-contained documents.
- open-icon is the explicit yardstick (P1 = manage `src/icons`; P2 = reproduce
  the raw→lib build as export profiles).
- Workspace UI: grid gallery first; optional canvas view later.
- Tokens bind by **colour-slot matching** (outline=`#010101` etc.), not path ids.
- Sequencing: workspace-first (P0 foundation → P1 workspace → P2 export
  profiles+containers → P3 tokens → P4 editor core → P5 pen/booleans → P6
  interchange). AI icon generation: far-future, after workspace+editor.
- Save contract: **normalise on first save**; semantic equality + idempotence;
  Fekthor only writes files the user actually edited.
- **Containers**: a container is a normal SVG in the workspace + a slot rect
  (position/fit rule) stored in the workfile; content icons declare container
  memberships; export composes the matrix (`{icon}-{container}.svg`).
- This repo (`fekthor`) is the repo of record for the pivot. The trace-editing
  batch developed on imageKid's `feat/fekthor-trace` (staircase fix, always-on
  editing toolkit, break/merge/remove, smooth handles, multi-select/marquee,
  colour bar, backspace delete, selection copy/export, Edit view mode,
  reconvert warning, home launcher) is ported here as step 0.

## Step 0 — consolidation (local)

- **0a.** Land the imageKid batch on its `feat/fekthor-trace` branch (three
  conventional commits: engine fixes / editor toolkit / app shell).
- **0b.** Port the batch into this repo, translating paths
  (`packages/FekthorKit` → `swift/FekthorKit`,
  `apps/native-macos/Sources/FekthorTrace` → `apps/fekthor-macos/Fekthor`; the
  rename half is a no-op here — this app is already Fekthor /
  `app.hakobs.fekthor`). Mirror the 3-commit split. This brings the batch's
  `Editing.swift` ops (`removingAnchor`/`mergedSegment`/`reversed`/
  `translatedPath`) that step 7 delegates to.
  Verify: `npm run engine:test && npm run macos:build`.
- **0c.** Doc sync (this file + ROADMAP/DECISIONS/IMPLEMENTATION-STATUS/AGENTS).

## P0 — foundation (each step = one verifiable commit)

New engine code in `swift/FekthorKit/Sources/FekthorKit/`, tests in
`swift/FekthorKit/Tests/FekthorKitTests/`, app code in
`apps/fekthor-macos/Fekthor/`.

Confirmed reuse: `RefinedPath`/`RefinedSegment` (`PathRefine.swift`,
`Equatable`/`Sendable`), `Editing.cubicized` (arc→cubic ≤90° spans),
`SVGExport.num`/`hex` formatting conventions, `PathBuilder.closed/open`,
`CGPathBuilder`, `Rasterizer` (P1 thumbnails), `EnvelopeBuilder` (P2
outline-strokes sibling).

1. **Model v2** (`Model2.swift`): `GraphicDocument{viewBox, rootAttributes,
   hadXMLDeclaration, nodes:[GraphicNode]}`; `GraphicNode = .shape | .group |
   .raw` (raw = verbatim passthrough); `ShapeNode{kind, style, attributes,
   transform?}`; `ShapeKind = .path([RefinedPath]) | .line | .polyline |
   .polygon | .rect | .circle | .ellipse` (primitives stay primitives for
   round-trip). Style = **ordered** `[StyleDeclaration]` with typed values
   (paint / number+unit / keyword / raw-verbatim), origin-tagged (presentation
   attribute vs `style=""` vs stylesheet) + computed accessors; fill AND stroke
   coexist; unknown props round-trip verbatim; `currentColor` / `var(--x,…)`
   preserved as raw paints.
2. **Trace→editor bridge** (`Model2Bridge.swift`, one-way): fills/strokes/
   primitives/gradients of `VectorDocument` map losslessly.
3. **Parsers** (`SVGPathData.swift` + `SVGStyle.swift`): full `d` grammar
   (MLHVCSQTAZ upper/lower, implicit repeats, compact numbers `.5`/`5e-2`,
   arc→endpoint-to-centre→`.arc` or cubics), inline-style parser (unknown →
   raw verbatim).
4. **SVG reader** (`SVGReader.swift`): Foundation XML; canonical writer order
   mitigates attribute-order dependence; groups recursive;
   `defs/style/clipPath/unknown` → raw nodes (plus a trivial `.class` resolver:
   render effective style, keep the `<style>` block); transforms kept raw +
   parsed matrix.
5. **SVG writer** (`SVGWriter.swift`): deterministic + idempotent
   (`write(read(write(read(f)))) == write(read(f))`); corpus-style numbers
   (≤2dp, `.5`, no `-0`, locale-safe); style declarations in stored order;
   primitives as native elements; arcs → cubics by default
   (`SVGWriteOptions(emitArcs:)` for trace parity); root attrs / XML decl only
   if the source had them.
6. **Round-trip corpus suite**: fixtures under
   `Tests/FekthorKitTests/Fixtures/openicon/` (`Package.swift` test
   resources): idempotence, model equality, normalised diff vs source,
   geometry deviation < 0.05. Seed fixtures mimic open-icon conventions;
   replace/extend with ~40 real icons locally. Env-gated full-corpus smoke:
   `FEKTHOR_ICON_CORPUS=~/Repositories/_projects/open-icon/src/icons swift test`.
7. **Editing2** (`Editing2.swift`): anchors/handles/remove/translate/recolour
   on `ShapeNode`, delegating to `Editing` internals (incl. the ported batch
   ops — depends on 0b); primitives expand to `.path` on first anchor edit;
   transform bakes on first geometry edit.
8. **Workfile v1** (`Workfile.swift`): Codable JSON — `version, folder?
   (path + security-scoped bookmark), artboards? [{name, svg}]` (geometry
   embedded as SVG text — single serialization path); `categories?/
   exportProfiles?/styleTokens?/containers?` forward-compatible stubs;
   `.sortedKeys` deterministic encode; unknown-key-tolerant decode. App gains
   the `com.apple.security.files.bookmarks.app-scope` entitlement.
9. **Editor session + canvas** (`EditorSession.swift`,
   `EditorCanvasView.swift`): session (document, selection, snapshot undo,
   fileURL+kind, dirty) split from trace-only `ConversionModel`; canvas
   renders GraphicNode via `CGPathBuilder.path(for: ShapeKind)`; interaction
   follows the ported `EditCanvasView` patterns (temporary duplication
   accepted; unification is the first P1 refactor).
10. **File menu** (`FekthorApp.swift`, `ContentView.swift`): New (⌘N), Open
    (⌘O: svg→editor, fekthor→workfile, raster→trace flow), Save (⌘S, in
    place), Save As; sandbox security scope held for the session. **P0 gate**:
    open a real `src/icons/…​.svg`, move one anchor, ⌘S; the file re-opens in
    Fekthor AND renders correctly in a browser; second save is byte-identical;
    untouched files are never rewritten.

Steps 1–6 and 8 are engine-only (new files); 7, 9, 10 sit behind the step-0b
port. Resolved without further input: arcs→cubics default; CSS-class icons
render-resolved but preserved; two parallel canvases through P0.

## After P0 (agreed outlines)

- **P1 Workspace**: folder-backed gallery (category sections, live
  `Rasterizer` thumbnails, search, rename, move-between-categories = file
  move, FSEvents), adopt open-icon `src/meta/*.json`, drop-PNG→trace→new
  entry. First refactor: unify `EditCanvasView` with `EditorCanvasView` via
  the bridge.
- **P2 Export profiles + containers**: action pipeline (outlineStrokes
  constant-width expand — sibling of `EnvelopeBuilder` —, flatten, fit/resize,
  recolour→hex/currentColor/`var(--icon-*)` with calc fallbacks, PNG sizes),
  naming templates, batch runner; container slot rects + memberships + matrix
  export `{icon}-{container}.svg`; acceptance = reproduce open-icon
  `lib/icons` output.
- **P3 Tokens**: colour-slot store in workfile, slot matching, propagation
  rewrites (only edited-by-propagation files), Styles panel, draw-with-style.
- **P4+**: transforms/group/z-order/style panel; pen/booleans; foreign-SVG
  import, PNG/PDF export, snapping.
- **Far-future (logged)**: on-device AI icon generation conditioned on the
  workspace's style standards.

## Verification

- Engine: `npm run engine:test` (all suites incl. round-trip corpus); the
  env-gated full-corpus smoke above.
- App: `npm run macos:build`.
- Manual P0 gate: the step-10 flow on a real open-icon file, plus a visual
  browser check of the saved SVG.

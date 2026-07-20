# Fekthor agent guide

This repository describes and implements Fekthor, a raster-to-editable-vector application focused on centreline and hybrid vectorisation.

## Read before changing code

Read these documents in order:

1. `README.md`
2. `docs/PRODUCT.md`
3. `docs/DECISIONS.md`
4. `docs/ARCHITECTURE.md`
5. `docs/VECTORIZATION-PIPELINE.md`
6. `docs/DOCUMENT-MODEL.md`
7. `docs/TESTING.md`
8. `docs/ROADMAP.md`

Feature work must remain consistent with the product principles and accepted decisions. When implementation evidence requires a change, update the relevant decision explicitly rather than quietly diverging from the documentation.

## Primary objective

Produce compact, editable vectors with correct semantics:

- Raster strokes should become real centreline paths with stroke properties.
- Solid regions should become filled shapes.
- Mixed artwork should contain both.
- Faithful vectorisation must not silently become generative redraw.

Visual similarity alone is not sufficient. Topology, node count, path structure and determinism are first-class quality requirements.

## Current implementation priority

Follow the first implementation backlog in `docs/ROADMAP.md`.

Do not begin with:

- AI integration.
- A large macOS application shell.
- Cloud services.
- Accounts or sync.
- Extensive export formats.
- A complete vector editor.

Begin with the Rust research core, fixtures, diagnostics, graph extraction, width estimation, Bézier fitting and SVG render-back comparison.

## Proposed repository structure

```text
fekthor/
├── apps/
│   └── macos/
├── crates/
│   ├── fekthor-core/
│   ├── fekthor-cli/
│   ├── fekthor-svg/
│   └── fekthor-testkit/
├── docs/
├── fixtures/
├── scripts/
└── .github/workflows/
```

Do not create duplicate geometry models in Swift and Rust. The Rust document model is authoritative; Swift receives stable DTOs and sends semantic commands.

## Engineering rules

### Determinism

- Identical input, configuration and engine version must produce identical structural output.
- Do not depend on hash-map iteration order.
- Stable-sort regions and elements before serialisation.
- Parallel work must merge in stable order.
- Randomised tests must record and report seeds.

### Geometry

- Reject NaN and infinite coordinates at boundaries.
- Use named tolerances rather than scattered numeric literals.
- Preserve topology before optimising visual error.
- Do not expand strokes to outlines internally unless an operation explicitly requires it.
- Quantise only at export.
- Keep source coordinates and transforms explicit.

### Pipeline stages

- Stages accept immutable inputs and return versioned outputs.
- Cache keys include source revision, stage version, parameters, resolution and region revision where relevant.
- A region-level failure should return a warning and partial result when safe.
- Diagnostics must be available for every new processing stage.

### Errors

- Return structured errors.
- Never panic across the native boundary.
- Preserve the previous valid result when a recomputation fails.
- Include region or stage context without leaking image content into production logs.

### Performance

- Implement the correct scalar CPU path first.
- Add benchmarks before optimisation.
- Parallelise independent regions only after deterministic behaviour is established.
- Avoid GPU or unsafe complexity without measured evidence.
- Track time and peak memory for representative fixtures.

### Privacy

- Core processing is offline.
- Do not introduce network calls into the engine.
- Do not upload fixtures, source images or generated paths to external services.
- Optional future model or cloud work must follow `docs/PRIVACY-SECURITY.md`.

### Dependencies

- Prefer small, focused dependencies.
- Record why a native or geometry dependency is needed.
- Verify the exact licence and transitive implications before adoption.
- Do not copy code from reference tracers without documented licence compatibility.
- Keep lockfiles committed.

## Coding style

### Rust

- Use stable Rust unless an accepted decision requires nightly.
- Format with `rustfmt`.
- Lint with Clippy and treat relevant warnings as errors in CI.
- Keep unsafe code isolated, documented and tested.
- Prefer explicit domain types over tuples for coordinates, widths, IDs and revisions.
- Use newtypes for identifiers.
- Document invariants on topology and geometry structures.
- Avoid hidden global state.

### Swift

- Use Swift concurrency for processing coordination.
- Keep engine work off the main actor.
- Use native document and undo behaviour.
- Avoid one SwiftUI view per vector node or path.
- Keep AppKit integration behind focused components.
- Preserve full keyboard and accessibility support for every command.

## Tests required with changes

### Algorithm change

Include:

- Unit tests.
- At least one fixture demonstrating the intended improvement or fixed failure.
- Before/after metrics.
- Diagnostic artefacts when results change materially.
- A note about topology and node-count impact.

### New pipeline stage

Include:

- Stage contract.
- Version identifier.
- Cache invalidation behaviour.
- Structured error cases.
- Diagnostic output.
- Performance measurement.

### Document-model change

Include:

- Format version impact.
- Migration or explicit statement that no persisted format exists yet.
- Serialisation round-trip tests.
- SVG/export impact.

### UI change

Include:

- Keyboard route.
- Accessibility labels and behaviour.
- Undo behaviour for geometry changes.
- Processing cancellation or stale-result handling where applicable.

## Fixture policy

- Prefer generated fixtures for exact ground truth.
- Real fixtures require documented usage rights.
- Keep the original input unchanged.
- Store structural expectations in metadata rather than relying only on golden pixels.
- Never update golden output merely to make tests pass; inspect and explain the change.

## Commit and pull request style

Use Conventional Commits, for example:

- `feat(core): build skeleton topology graph`
- `fix(bezier): preserve closure when simplifying loops`
- `test(fixtures): add T-junction width regression`
- `docs: record native bridge decision`
- `perf(core): reuse region distance transforms`

Pull requests should state:

- Problem and intended result.
- Relevant decision or roadmap item.
- Algorithm or architecture change.
- Tests and fixtures.
- Quality metrics before and after.
- Known failure cases.
- Screenshots or diagnostic artefacts when visual output changes.

## Definition of done

A task is complete when:

- Behaviour is implemented.
- Tests cover success and important failures.
- Output remains deterministic.
- Diagnostics are sufficient to investigate regressions.
- Performance is measured for algorithmic work.
- Documentation is updated when contracts or decisions change.
- No unrelated geometry changes occur in incremental workflows.
- Licences are reviewed for added dependencies.

## Decision escalation

Stop and document an open decision before proceeding when work would:

- Replace real strokes with outlines by default.
- Make cloud access necessary.
- Add generative behaviour to faithful mode.
- Create a second authoritative document model.
- Introduce a dependency with unclear distribution rights.
- Change persisted project compatibility.
- Trade topology correctness for an unmeasured visual improvement.

The engine quality is the product. Keep the implementation narrow until the centreline and hybrid pipeline is proven against fixtures.

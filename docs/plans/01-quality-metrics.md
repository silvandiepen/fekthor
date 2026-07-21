# Plan 01 — Mode-aware quality metrics & evaluation harness

**Goal:** honest, mode-appropriate scoring of every conversion, plus a one-command
evaluation harness over the fixture set. Everything later (auto mode, regression gates,
tuning) builds on this. Do this plan first.

## Why

The current single metric (`Comparer.compare` → exactPct/PSNR in
`swift/FekthorKit/Sources/FekthorKit/Compare.swift`) is only meaningful for fill modes.
For Strokes it is actively misleading (black lines vs a colour source ≈ 0% — the app
already hides it, `ContentView.swift` Result section). Auto mode (plan 06) needs a score
that can *compare modes against each other*, which pixel-exactness cannot do.

## Deliverables

### 1. `QualityScore` in a new `Quality.swift`

```swift
public struct QualityScore: Codable, Sendable {
    public var fidelity: Double      // 0…1, mode-aware (below)
    public var simplicity: Double    // 0…1, from node/path counts (below)
    public var overall: Double       // 0.75*fidelity + 0.25*simplicity
    public var detail: [String: Double]  // raw sub-metrics for diagnostics
}
public enum Quality {
    public static func score(source: RasterImage, document: VectorDocument,
                             rendered: RasterImage, mode: Mode) -> QualityScore
}
```

`rendered` is the existing `Rasterizer.render` output at working size.

**Fidelity per mode:**

- **Shapes:** `0.5*pixel + 0.5*edge`.
  - `pixel` = exactPct(tol 8)/100 from the existing `Comparer`.
  - `edge` = 1 − clamp(meanChamfer/4, 0, 1), where meanChamfer is the symmetric mean
    Chamfer distance (in px) between Sobel edge maps (threshold: gradient magnitude > 48
    on luminance) of source and rendered. Implement Chamfer with a two-pass 3-4 distance
    transform over each edge bitmap (O(n)); do **not** use per-pixel nearest search.
- **Strokes:** pixel metrics on colour sources are meaningless, so compare **line masks**:
  - `srcMask` = `Foreground.dark(source, threshold: 128)` if the source `isLineArt`
    (reuse `StrokesMode.isLineArt`), else the edge map of the source (Sobel, as above) —
    because coloring-plate output should trace the source's edges.
  - `outMask` = dark pixels of `rendered` (luminance < 128).
  - `fidelity` = 1 − clamp(symmetricChamfer(srcMask, outMask)/6, 0, 1).
- **Gradient:** `0.35*pixel(tol 12) + 0.65*psnrTerm`, psnrTerm = clamp((PSNR−18)/18, 0, 1).
  Gradients never match exactly; PSNR is the right lens.

**Simplicity:** `1 − clamp(log10(max(nodes,10)/10)/3, 0, 1)` — 10 nodes→1.0, 10k→0.0 —
times a path-count factor `1 − clamp(paths/400, 0, 0.3)`. Use `document.nodeCount` and
`document.elements.count`.

### 2. Wire into `Fekthor.convert`

Add `public var quality: QualityScore` to `Fekthor.Result` (`Fekthor.swift`), computed
after render-back. Keep the existing `metrics` field (CLI/JSON compatibility). Show
`overall` as a percentage in the app's Result section and status bar for **all** modes
(this replaces the hidden-metrics special-casing for Strokes with one honest number;
keep the extra per-mode rows as they are).

### 3. Evaluation harness: `fekthor eval`

New subcommand in `swift/FekthorKit/Sources/fekthor/main.swift`:

```
fekthor eval [--fixtures DIR=fixtures/inputs] [--out DIR=out/eval] [--json]
```

For each PNG in the fixtures dir, run **all three modes** at 1024 working size
(`RasterImage.scaled(maxDimension: 1024)` — same as the app), write per-run
`render.png`/`vector.svg`, and emit a table:

```
fixture            mode      overall  fidelity  simplicity  nodes  paths  ms
artist-lineart     strokes     0.91      0.94        0.82    439     64   210
…
```

`--json` writes `out/eval/report.json` with the same data. Exit code 0 always (it is a
report, not a gate).

### 4. Regression gate in tests

Add `EvalRegressionTests` (XCTest) asserting per-fixture-per-canonical-mode **minimum
overall scores**, set ~0.03 below the measured baseline at implementation time so noise
doesn't flake but regressions fail. Canonical pairs: lineart→strokes, flat→shapes,
thor-flat→shapes, 3d→gradient, thor-3d→gradient. Bump the floors upward as later plans
improve results (each later plan says to).

## Acceptance criteria

- [x] `fekthor eval` runs over the 5 fixtures × 3 modes in < 60s total and prints the table.
      (~8s on Apple Silicon; table aligned.)
- [x] Strokes on `artist-lineart` scores overall ≥ 0.75 with the *new* metric (it looks
      good; the metric must agree), while Strokes on `artist-3d` scores clearly lower than
      Gradient on `artist-3d` — sanity that the metric ranks modes correctly per family.
      (Measured: lineart→strokes 0.832; artist-3d strokes 0.029 vs gradient 0.480.)
- [x] Deterministic: two eval runs produce identical report.json (timestamps excluded).
      (Required fixing a latent cross-process non-determinism — see Attempts below.)
- [x] All existing tests pass; new tests added for Chamfer (known masks → known distance)
      and for score monotonicity (adding noise to rendered lowers fidelity).

## Measured baselines (2026-07-21, release, 1024 working size)

Canonical pairs and the regression floors (~0.03 below baseline) set in
`EvalRegressionTests`:

| fixture | mode | overall | floor |
|---|---|---|---|
| artist-lineart | strokes | 0.832 | 0.80 |
| artist-flat | shapes | 0.679 | 0.65 |
| thor-flat | shapes | 0.400 | 0.36 |
| artist-3d | gradient | 0.480 | 0.45 |
| thor-3d | gradient | 0.221 | 0.19 |

## Attempts / deviations

- **Cross-process determinism fix (required, not a conversion change).** The eval
  determinism criterion exposed that the pipeline was byte-stable *within* a process
  but not *across* processes: `ComponentMerge.neighbors` iterated a `Set<Int>` and
  `PlanarMap.faces` sorted equal-area faces from a `Dictionary` map with no tie-breaker.
  Swift seeds its hasher per process, so `Set`/`Dictionary` iteration order — and thus
  the output geometry — changed run to run, violating global invariant #1. Fixed by
  sorting the neighbour list and adding a `label` tie-breaker to the face sort. This
  restores determinism without altering the intended geometry (measurement-only scope
  preserved; scores are unchanged within noise).

## Guardrails

- Chamfer/Sobel run on the **working-size** images only (≤2048²); keep them O(n).
- Do not change any conversion behaviour in this plan — measurement only.
- `detail` map must include the raw sub-metrics (pixel, edge, chamfer, psnr, nodes) so
  later tuning can read them without recomputation.

# Plan 06 — Auto mode: pick the right conversion automatically

**Goal:** a fourth mode, **Auto** (the new default), that detects which conversion suits
the image — Strokes for line drawings, Shapes for flat art/logos, Gradient for shaded
renders — while the user can still switch manually and tweak everything. Depends on
plans 01 (mode-aware scoring — the decider) and ideally lands last, after 02–05 have
raised each mode's quality.

## Design: cheap features first, trial conversions to break ties

### Stage A — feature classifier (fast, runs on a 256px thumbnail)

Compute on `img.scaled(maxDimension: 256)`:

| Feature | How | Signal |
|---|---|---|
| `greyness` | mean per-pixel channel spread (max−min RGB) | line art ≈ 0 |
| `paletteCount` | `quantizeAuto(maxColors: 12, minFraction: 0.01).palette.count` | flat art small, renders large |
| `flatCoverage` | fraction of pixels within tol 10 of their palette colour | flat art high, renders low |
| `gradientEnergy` | mean |∇luminance| over non-edge pixels (Sobel < 48) | renders high, flat ≈ 0 |
| `inkFraction` | `Foreground.dark(…,128).count / n` | line art low (5–25%) |
| `edgeDensity` | Sobel-edge pixel fraction | line drawings high relative to ink |

Decision (confidence = margin between best and second rule score):

- `greyness < 12 && paletteCount ≤ 2 && inkFraction < 0.35` → **Strokes** (line art).
- else `flatCoverage > 0.90 && gradientEnergy < 1.2` → **Shapes**.
- else `gradientEnergy > 2.5 && paletteCount ≥ 8` → **Gradient**.
- Otherwise → Stage B.

Thresholds are constants in one place (`AutoMode.swift`) with a table-driven unit test
per fixture; tune against the five fixtures + the synthetic logo fixtures (plan 04).

### Stage B — trial conversions (only when Stage A is unsure)

Run all three modes on the 256px thumbnail (fast path: same pipeline, working size 256),
score each with plan-01 `Quality.score`, pick the highest `overall`. Deterministic; ≤0.4s
total budget. Cache the decision per image hash so slider changes don't re-run it.

### API & UI

- `Mode` gains `.auto`. `Fekthor.convert(img, mode: .auto, …)` resolves via
  `AutoMode.detect(img) -> (resolved: Mode, confidence: Double, features: [String: Double])`
  then converts with the resolved mode; `Result` gains `resolvedMode: Mode`.
- App: mode picker shows **Auto · Shapes · Strokes · Gradient** (Auto default). While in
  Auto, the inspector shows a subtle line "Detected: Shapes" (from `resolvedMode`) and
  displays the *resolved* mode's controls. Picking a concrete mode overrides; switching
  back to Auto re-detects. Persist nothing — detection is per-image.
- CLI: `--mode auto` (new default), prints `mode=auto→shapes …` in the summary line and
  `resolvedMode` in metrics.json.

## Acceptance criteria

- [ ] All five fixtures resolve to their canonical modes (lineart→strokes, flat+thor-flat
      →shapes, 3d+thor-3d→gradient) via **Stage A alone** (table test asserts both the
      resolution and that confidence cleared the trial threshold).
- [ ] A deliberately ambiguous synthetic (flat shapes + one soft gradient area) reaches
      Stage B and picks the plan-01-best mode (test pins the expected winner).
- [ ] Auto adds ≤80ms (Stage A) on a 1024 conversion; Stage B ≤400ms when triggered.
- [ ] Switching Auto→manual→Auto in the app is stable (no re-detection loop; detection
      runs once per loaded image, cached by content hash).
- [ ] Determinism, tests, CI; eval harness gains an `auto` row per fixture asserting the
      resolved mode.

## Guardrails

- Detection must never change an explicit user choice; only `.auto` resolves.
- Stage B uses the plan-01 score *unchanged* — if the score misranks a family, fix the
  metric (plan 01), never special-case Stage B.
- Keep every threshold in `AutoMode.swift` with a comment linking to the fixture that
  motivated it; no magic numbers scattered in call sites.

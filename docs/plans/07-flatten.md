# Plan 07 — Flatten: hue-aware colour reduction (shaded → flat)

**Goal:** reducing colours should collapse **shade families** — touching regions with the
same hue but different lightness (a beard's many blonds, a face's skin tones, a helmet's
blues) — into single flat colours, while the shapes stay. Reference pair committed in the
repo: `fixtures/inputs/thor-3d.png` (shaded source) should become, in Shapes mode with
reduced colours, something like `fixtures/references/thor-3d-flattened.png` (the flat
target: one-two blonds for the whole beard, flat skin, flat helmet blues, cape still a
*distinct* red from the background red). Same shapes — fewer colours.

Depends on plan 01 (metrics). Independent of 02–06; slots naturally after 04 (Shapes).

## Why current colour reduction can't do this

All colour distances in the engine are **Euclidean RGB** (`ColorQuantizer.dist2`,
`ComponentMerge.dist2`). In RGB, "dark blond → light blond" can be a *larger* distance
than "blond → grey-blue", so lowering the colour count merges across hues before it
merges shades — producing mud instead of flat art. Flattening requires a perceptual,
**hue-weighted** metric.

## Design

### 1. Perceptual colour space: Oklab (new `OklabColor.swift`)

Implement sRGB → Oklab (closed-form: linearise sRGB, LMS matrix, cube root, Lab matrix —
use the published Björn Ottosson constants; unit-test against 5 known reference values).
Work in `(L, a, b)` floats. Define the **flatten metric**:

```
d²(c1, c2) = wL·ΔL² + wC·(Δa² + Δb²)
wL = 1 − 0.85·flatten     // flatten ∈ 0…1 (UI slider)
wC = 1 + 2.0·flatten
```

- `flatten = 0` → near-neutral perceptual distance (safe default ≈ current behaviour).
- `flatten = 1` → lightness differences almost free, hue/chroma differences expensive:
  shades of one hue collapse; different hues stay apart.
- Near-neutrals need no special-casing: greys/blacks/whites have a≈b≈0, so they are
  hue-less in Oklab and separate from colours by chroma — black eyes never merge into
  blond, but *do* merge across dark-grey shades. This is exactly the wanted behaviour.

### 2. Where the metric applies (three call sites, one constant source)

1. **Palette family clustering** (`ColorQuantizer`): quantize *fine* first (auto or
   k=32 as today), then agglomeratively cluster the palette entries themselves with the
   flatten metric until the user's Colours count remains (complete-linkage over the ≤32
   entries — trivially cheap, deterministic tie-break by palette index). Every pixel's
   label maps through its family. This is the "reduce colours" step the user described.
2. **Region merging** (`ComponentMerge`): `colorThreshold` comparisons switch to the
   flatten metric (region mean colours converted once to Oklab; keep the existing
   union-find/area machinery unchanged).
3. **Plan 05 gradient merging** is *not* touched — Gradient keeps shading by design;
   Flatten is a Shapes-mode behaviour.

### 3. Representative colour: dominant shade, not mean

A merged shade family must not become the muddy average of highlight and shadow. The
family's output colour = the member palette entry with the **largest pixel coverage**
(area-weighted mode). The flat Thor reference shows this: the beard becomes the mid
blond that dominates, not a blend with its white highlights. Deterministic tie-break:
lower palette index. (Plan 04's exact-colour rule then applies to that entry.)

### 4. UI & API

- New **Flatten** slider (0–100%, default 0%) in Shapes mode, next to Colours.
  `Fekthor.Options.flatten: Double = 0`. At 0 the pipeline must be byte-identical to
  today (regression guarantee); the slider only *adds* merging pressure.
- When Auto colours is on, Flatten applies at stage (2) and to family clustering of the
  auto palette; when off, the Colours slider count is reached *via* family clustering
  (never by re-running k-means with lower k — that reintroduces RGB mud).
- CLI: `--flatten 0..1`.

## Acceptance criteria

- [x] Unit: Oklab conversion matches reference values (±0.002); flatten metric ranks
      (lightBlond,darkBlond) closer than (blond,steelBlue) at flatten ≥ 0.5, while RGB
      distance ranks them the other way (encode this inversion as the test).
      *(`OklabColorTests`)*
- [x] Synthetic: a sphere shaded in 6 blues on a 3-green background, Shapes with
      Colours=2, Flatten=70% → exactly 2 fills (one blue, one green), sphere silhouette
      preserved (IoU vs the true disc ≥ 0.97). *(`FlattenTests.testShadedSphere…`)*
- [x] `thor-3d.png`, Shapes, Colours≈12, Flatten≈70%: beard resolves to ~1 blond, face
      flat skin, helmet blues reduced, **cape red stays a separate fill from background
      red**, eyes stay black, total fills = 11 (≤ 45). Reads as the same flat-art style
      as `fixtures/references/thor-3d-flattened.png` (shapes match; palette within
      reason). This is the headline demo. *(`FlattenTests.testThorFlattenHeadline`)*
- [x] Flatten=0 produces byte-identical SVG to pre-plan output on all fixtures
      (`FlattenTests.testFlattenZeroByteIdentical` + eval floors unchanged), and
      `artist-flat` is visually unchanged at Flatten ≤ 30% (PSNR ≥ 30 dB / exact ≥ 90%,
      no fill fragmentation — see Attempts on the overall-score nuance).
- [x] Determinism (`testFlattenDeterministic`), tests, CI, eval floors intact; perf
      budget holds (family clustering is over ≤32 palette entries — negligible; a
      1024-px thor Flatten conversion runs in ~0.9 s).

## Attempts / deviations

- **Region merging emits the dominant family colour, not the mean.** Plan §2 asks the
  region-merge stage (`ComponentMerge`) to switch its colour comparisons to the flatten
  metric — done. But its default emission is the area-weighted *mean* of a merged region,
  which reintroduces intermediate shades (a merged beard became a muddy gradient of ~250
  distinct means). Under Flatten the merge now emits each region's **dominant source
  palette entry** (mode, tie-break lower index — plan §3), so colours stay exactly the
  reduced flat palette.
- **Same-colour regions group into one face (`ShapesMode.groupByColour`).** With
  per-component labels a shaded source fragmented into hundreds of fills (thor: 264–485).
  After the flatten merge, labels sharing an identical colour collapse to one PlanarMap
  face, so the fill count drops to ~the palette size (thor: 11 fills) while boundaries
  stay clean (ComponentMerge already absorbed specks, so node counts don't explode the
  way a naive colour-grouping without speck absorption did — 1.7k vs 0.5k nodes on
  artist-flat). Grouping is deterministic (first-appearance order, no dictionary leak).
- **Distinct-colour guard is area-based, not purely distance-based.** A single flatten
  distance can't separate "collapse this shade" from "keep this distinct colour":
  artist-flat's two navy shades sit at d²≈0.0027 while thor's blond↔skin-highlight sits
  at d²≈0.0105 — the *flat* art's distinct pair is the *closer* one. So Flatten leans on
  region area (only sub-`minArea` specks are absorbed) plus a distinct-hue guard
  (`flattenSeparation`) that keeps far-hued small features (black eyes border skin, a red
  accent) at any Flatten value. Family clustering never runs when the fine palette
  already has ≤ the target count (thor auto-returns 11 flat colours at Colours=12), so the
  metric-driven collapse is exercised where it matters (the sphere: 9→2).
- **"artist-flat unchanged at ≤30%" is asserted on visual fidelity, not overall score.**
  At Flatten 0.3 artist-flat renders identically to Flatten 0 (PSNR 31.4 dB, exact 93%,
  no fragmentation) but produces a *cleaner* 7-colour flat palette instead of Flatten 0's
  17 mean-variant fills. The mode-aware `overall` dips (~0.72→0.58) because its edge
  sub-metric rewards those extra mean-variant fills — a metric artefact, not a visual
  regression. The regression test therefore guards PSNR/exact/fill-count; the eval floors
  (measured at Flatten 0, the default) are untouched.

## Guardrails

- One metric implementation, one place (`OklabColor.flattenDistance`), used by every
  call site — no per-file copies of the weights.
- Family clustering must respect plan 04's distinct-small-colour guard (a tiny red dot
  on white survives any Flatten value).
- Merging remains **adjacency-based** at region level (only touching regions merge);
  family clustering at palette level is global by design (that is what "reduce colours"
  means) — document this asymmetry in code comments.
- Do not let Flatten leak into Strokes/Gradient paths; it is a Shapes-mode option
  (`isLineArt` routing and gradient banding are unaffected).
- **Orchestrator gate note (post-acceptance):** the dominant-shade pick is sensitive to
  working resolution and Flatten strength — at 2048 px native with Flatten 0.7 the beard
  family's dominant shade flips to a skin tone, while 1024 px (the app default) at 0.7,
  or 2048 px at Flatten 0.4–0.6, keep it blond. Fine at the app's default pipeline;
  a future robustness pass could pick the dominant shade in a resolution-independent way
  (e.g. area fractions from the fine palette rather than bucket counts).

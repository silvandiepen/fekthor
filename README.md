# Fekthor

Fekthor is a native raster-to-vector application focused on producing **clean, editable vectors**, not merely tracing the outside edge of every dark pixel.

The primary problem it solves is centreline vectorisation. A raster stroke should normally become one SVG path with a real `stroke`, rather than a closed filled outline representing both sides of the original line.

```svg
<path
  d="M 120 180 C 160 140, 220 150, 260 170"
  fill="none"
  stroke="#000"
  stroke-width="6"
  stroke-linecap="round"
  stroke-linejoin="round"
/>
```

Fekthor also supports ordinary filled-shape tracing and combines both approaches in a hybrid mode. In a line-art illustration, outlines can remain editable strokes while genuinely solid regions, such as pupils or silhouettes, remain filled shapes.

## Product principles

1. **Faithful before generative** — the default result should reproduce the source, not reinterpret it.
2. **Real strokes where the source contains strokes** — editable width, caps, joins and centreline geometry.
3. **Hybrid output** — strokes and fills may coexist in the same document.
4. **Low path count** — prefer a small number of meaningful Bézier paths over thousands of tiny contours.
5. **Local and private by default** — vectorisation should work fully offline.
6. **Visible uncertainty** — ambiguous regions should be inspectable and correctable.
7. **Non-destructive workflow** — the original image, preprocessing settings and vector result remain recoverable.
8. **Calm native interface** — importing, comparing, correcting and exporting should require little setup.

## Core modes

- **Smart** — classifies regions and produces a mixture of stroke paths and filled shapes.
- **Strokes** — performs centreline extraction and emits stroked open or closed paths.
- **Shapes** — performs conventional contour tracing and emits closed filled paths.
- **Clean redraw** — optional AI-assisted reinterpretation, clearly separated from faithful vectorisation.

## Initial platform and architecture

The initial product is a native macOS application built with SwiftUI. The vectorisation engine is a reusable Rust library exposed through a narrow native interface. The engine is deterministic and local-first; optional ML components assist classification and repair but do not replace the geometric pipeline.

## Repository documentation

- [Product plan](docs/PRODUCT.md)
- [Feature specification](docs/FEATURES.md)
- [User experience](docs/UX.md)
- [Technical architecture](docs/ARCHITECTURE.md)
- [Vectorisation pipeline](docs/VECTORIZATION-PIPELINE.md)
- [AI and model strategy](docs/AI.md)
- [Internal document model and formats](docs/DOCUMENT-MODEL.md)
- [Quality and testing](docs/TESTING.md)
- [Roadmap](docs/ROADMAP.md)
- [Research plan](docs/RESEARCH.md)
- [Privacy and security](docs/PRIVACY-SECURITY.md)
- [Architecture decisions](docs/DECISIONS.md)
- [Agent implementation guide](AGENTS.md)

## Implementation tracking

- [MVP master plan](../../issues/8)
- [Phase 0 — Research foundation](../../issues/1)
- [Phase 1 — Centreline stroke engine](../../issues/2)
- [Phase 2 — Smart hybrid vectorisation](../../issues/3)
- [Phase 3 — Native macOS workflow](../../issues/4)
- [Phase 4 — Correction tools and exports](../../issues/5)
- [Phase 5 — Public-release hardening](../../issues/6)
- [Later — Optional on-device AI](../../issues/7)

## Current status

The complete product and engineering plan is documented. Implementation should begin with the fixture-driven research foundation and deterministic centreline spike before substantial UI or AI work.

## Licensing

No project license has been selected yet. Dependencies and reference implementations must be reviewed before code is incorporated. Do not assume that a library being publicly available makes it suitable for redistribution in a closed-source or App Store product.

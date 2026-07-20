# Internal document model and file formats

## Purpose

Fekthor needs an internal representation richer than exported SVG. The document must preserve raster evidence, automatic classifications, user overrides, editable geometry and enough provenance to recompute only affected regions.

SVG remains an important export format, but it is not the project database.

## Coordinate system

- Document coordinates use source-image pixel units by default.
- The origin is the top-left in the internal model to align with raster processing.
- Exporters may transform to another coordinate convention when required.
- Coordinates use 64-bit floating-point values in the engine.
- The artboard records width, height and an optional source transform.
- Geometry must remain valid independently of display scale.

## Core entities

```text
Project
├── SourceAsset
├── ProcessingConfiguration
├── RasterEvidence
├── VectorDocument
│   ├── Artboard
│   ├── Layer[]
│   │   └── VectorElement[]
│   │       ├── StrokePath
│   │       ├── FillShape
│   │       └── Group
│   └── Palette
├── RegionRecord[]
├── EditRecord[]
├── ExportPreset[]
└── CacheManifest
```

## Project

A project records:

- Format version.
- Project ID.
- Created and modified timestamps.
- Source asset reference.
- Active engine version.
- Processing configuration.
- Vector document.
- Region classifications and overrides.
- Cleanup-mask revisions.
- Manual edits.
- Export presets.
- Optional cached intermediates.

The project must be forward-migratable. Unknown optional fields should be preserved where practical.

## Source asset

```json
{
  "id": "source-1",
  "embeddedPath": "source/original.png",
  "originalFilename": "drawing.png",
  "width": 2048,
  "height": 2048,
  "pixelScale": 1,
  "colorSpace": "sRGB",
  "orientationApplied": true,
  "contentHash": "..."
}
```

The content hash identifies whether the source changed and participates in cache keys.

## Processing configuration

Configuration should use user-facing concepts and retain advanced engine parameters separately.

```json
{
  "mode": "smart",
  "preset": "clean-line-art",
  "detail": 0.65,
  "smoothness": 0.55,
  "noiseRemoval": 0.2,
  "gapRepair": 0.1,
  "classificationBias": 0.0,
  "strokeWidth": { "mode": "auto" },
  "advanced": {},
  "pipelineVersion": 1
}
```

Values are normalised when practical. Presets expand into explicit values so reopening a project does not depend on a mutable preset definition.

## Vector document

### Artboard

```json
{
  "width": 2048,
  "height": 2048,
  "viewBox": [0, 0, 2048, 2048]
}
```

### Stable IDs

Every element, path, node and source region has a stable ID. IDs allow:

- Local recomputation.
- Undo commands.
- Selection restoration.
- Export metadata.
- Test comparisons that do not depend entirely on array position.

Automatic recomputation should retain IDs for unchanged semantic elements whenever possible.

### Stroke path

```json
{
  "type": "stroke",
  "id": "stroke-42",
  "layerId": "layer-1",
  "sourceRegionIds": ["region-17"],
  "closed": false,
  "segments": [
    {
      "type": "cubic",
      "from": [120.0, 180.0],
      "control1": [160.0, 140.0],
      "control2": [220.0, 150.0],
      "to": [260.0, 170.0]
    }
  ],
  "style": {
    "stroke": "#111111",
    "width": 6.0,
    "lineCap": "round",
    "lineJoin": "round",
    "miterLimit": 4
  },
  "classification": {
    "source": "automatic",
    "confidence": 0.94
  }
}
```

Later variable-width support should add a width profile without invalidating constant-width documents.

### Fill shape

```json
{
  "type": "fill",
  "id": "fill-8",
  "layerId": "layer-1",
  "sourceRegionIds": ["region-21"],
  "contours": [
    {
      "closed": true,
      "segments": []
    }
  ],
  "style": {
    "fill": "#111111",
    "fillRule": "evenodd"
  },
  "classification": {
    "source": "user",
    "confidence": 1.0
  }
}
```

A fill may contain multiple contours and holes.

### Group

Groups contain element IDs and optional transforms. Grouping should reflect useful source structure, not arbitrary processing batches.

### Layer

Initial documents may use one generated layer plus optional reference layers. The model should still support:

- Visibility.
- Lock state.
- Opacity.
- Blend mode where export supports it.
- Ordered child elements.

## Region record

A region record links raster evidence to vector output.

```json
{
  "id": "region-17",
  "bounds": [80, 100, 240, 190],
  "pixelArea": 10820,
  "automaticClass": "stroke",
  "automaticConfidence": 0.94,
  "userOverride": null,
  "elementIds": ["stroke-42"],
  "featureSummary": {
    "medianWidth": 6.1,
    "widthVariation": 0.12,
    "skeletonLength": 331.4,
    "endpointCount": 2,
    "junctionCount": 0
  },
  "revision": 3
}
```

Large binary masks should be stored in compact sidecar files rather than expanded into JSON arrays.

## Bézier representation

The engine should support line and cubic segments internally. Quadratic input may be normalised to cubic segments for a simpler editing and export model.

A path contains:

- Ordered segments.
- Open or closed state.
- Optional corner markers.
- Optional source sample ranges for diagnostics.
- Optional locked ranges that automatic refinement may not alter.

Path continuity must be explicit:

- Positional continuity is required between adjacent segments.
- Tangent continuity is optional and represented by node type or constraints.

## Classification state

Classification must distinguish:

- Automatic prediction.
- User override.
- Fallback caused by an engine failure.
- Generative suggestion not yet accepted.

Never overwrite the automatic prediction when the user overrides it. Retaining both allows “Use Automatic” and supports future comparison.

## Edit records

The undo system should use semantic commands:

- Set processing parameter.
- Set region classification.
- Split region.
- Merge regions.
- Apply cleanup-mask delta.
- Move node.
- Change handle.
- Set stroke width.
- Join endpoints.
- Delete element.
- Add manual path.

A persisted project does not need an unlimited event log, but it should store enough accepted manual operations to reproduce the document when disposable caches are missing.

## Revisions

Use revision counters at several levels:

- Source revision.
- Preprocessing revision.
- Region-map revision.
- Per-region revision.
- Vector-document revision.
- Per-element geometry revision.

Jobs carry the revisions they were created from. Results are discarded when their source revision no longer matches.

## Cache manifest

The cache records disposable intermediate artefacts:

```json
{
  "entries": [
    {
      "stage": "distance-transform",
      "key": "sha256:...",
      "path": "cache/distance-1.bin",
      "bytes": 16777216,
      "engineVersion": "0.1.0"
    }
  ]
}
```

Caches may be cleared without losing the ability to rebuild the project.

## Native `.fekthor` package

Suggested structure:

```text
Example.fekthor/
├── manifest.json
├── source/
│   └── original.png
├── document.json
├── settings.json
├── regions.json
├── edits.json
├── masks/
│   ├── cleanup.bin
│   └── region-index.bin
├── cache/
└── preview.png
```

### Required files

- `manifest.json`
- source asset or a resolvable security-scoped reference
- `document.json`
- `settings.json`
- user overrides and cleanup edits

### Disposable files

- Intermediate masks.
- Distance transforms.
- Skeleton caches.
- Rendered comparison images.
- Thumbnails that can be regenerated.

Embedding the source should be the default because it makes the document portable. A linked-source mode may be added for very large files.

## SVG export mapping

### Stroke path

```svg
<path
  id="stroke-42"
  d="M120 180 C160 140 220 150 260 170"
  fill="none"
  stroke="#111"
  stroke-width="6"
  stroke-linecap="round"
  stroke-linejoin="round"
/>
```

### Fill shape

```svg
<path
  id="fill-8"
  d="..."
  fill="#111"
  fill-rule="evenodd"
/>
```

### Metadata

Editable export may include a minimal Fekthor namespace containing source region IDs and element types. Web-optimised export should remove private metadata.

## SVG compatibility rules

- Always emit a `viewBox`.
- Avoid non-standard path commands.
- Use finite decimal values.
- Omit redundant attributes.
- Preserve real strokes unless expansion is explicitly selected.
- Use `fill-rule="evenodd"` when it simplifies hole representation predictably.
- Do not rely on CSS external to the SVG for core appearance.
- Validate exports by parsing and rasterising them in tests.

## PDF export

PDF should preserve vector geometry, strokes and fills. The exporter may use Core Graphics in the macOS app, while golden tests should compare rendered output and structural expectations where possible.

## Clipboard formats

When copying vector content, provide:

- SVG text.
- A vector PDF representation for native applications.
- A PNG preview as a fallback.
- Plain text only when the selection is valid SVG text.

## Version migration

Every persisted structure has a version. Migration rules should:

- Preserve source and accepted manual edits.
- Avoid silently changing geometry on open.
- Rebuild disposable caches.
- Keep a backup before destructive migration.
- Report when an old project can be opened read-only but not fully migrated.

## Numerical stability

- Reject NaN and infinite values at module boundaries.
- Use explicit tolerances in geometry operations.
- Quantise only during export, not in the editable model.
- Stable-sort elements before serialisation and export.
- Avoid depending on hash-map iteration order.

## Privacy

Project packages may contain the complete source image and diagnostics. The user should be told what is included when sharing a `.fekthor` project. Optimised SVG export should not include the source raster unless explicitly requested.

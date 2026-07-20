# Feature specification

This document separates the minimum viable product from the first complete release and later extensions. The order is deliberate: tracing quality and correction speed matter more than a large feature count.

## MVP

The MVP proves that Fekthor can produce structurally useful vectors from clean line art.

### Import

- Open PNG, JPEG, TIFF, HEIC and WebP images supported by the platform decoder.
- Drag and drop files into the application.
- Paste an image from the clipboard.
- Preserve the original file and metadata inside the project reference.
- Detect alpha, background colour, orientation and embedded colour profile.
- Warn when the source resolution is too low for reliable reconstruction.

### Canvas

- Pan and zoom.
- Fit image, actual size and fit selection.
- Source, vector, split, overlay and difference views.
- Adjustable source opacity.
- Pixel grid at high zoom.
- Selection highlighting for paths, fills and connected regions.

### Preprocessing

- Automatic background estimation.
- Grayscale conversion for monochrome workflows.
- Threshold control with automatic default.
- Light denoise and isolated-speck removal.
- Gap closing for small scan defects.
- Optional line darkening.
- Preview resolution and final resolution separation.
- Reset to source.

### Vectorisation modes

#### Smart

- Classify connected regions as Stroke, Fill or Uncertain.
- Run centreline extraction on stroke regions.
- Run contour tracing on fill regions.
- Preserve holes.
- Display confidence for uncertain classifications.

#### Strokes

- Skeletonise the foreground mask.
- Detect endpoints, junctions and loops.
- Convert pixel chains into smooth cubic Bézier paths.
- Estimate constant stroke width from the source.
- Use round caps and joins by default.
- Support open and closed stroke paths.
- Remove short spurs and scan artefacts.

#### Shapes

- Trace outer and inner contours.
- Simplify contours while respecting visual error.
- Emit closed filled paths.
- Preserve winding and holes.
- Merge small adjacent regions when appropriate.

### Global controls

The MVP should expose a small number of understandable controls rather than raw algorithm parameters:

- **Detail** — controls geometric fidelity and simplification.
- **Smoothness** — controls curve regularisation.
- **Noise removal** — controls minimum retained feature size.
- **Gap repair** — controls how aggressively broken strokes reconnect.
- **Stroke width** — Auto or fixed value.
- **Classification bias** — More strokes ↔ More shapes.

Advanced parameters may exist in a disclosure panel for testing, but should not dominate the product.

### Region correction

- Select a connected region.
- Change classification to Stroke, Fill or Ignore.
- Re-run only the affected region.
- Split incorrectly joined regions with a cut gesture.
- Merge selected regions.
- Restore automatic classification.
- Show the source mask associated with the selected vector element.

### Basic vector editing

- Select, move and delete a path.
- Edit Bézier nodes and handles.
- Add or remove nodes.
- Change stroke width, colour, cap and join.
- Change fill colour.
- Reverse path direction.
- Open or close a path.
- Join compatible endpoints.
- Break a path at a selected node.
- Simplify selected paths.
- Undo and redo all edits.

### Export

- SVG with strokes preserved.
- PDF with vector content.
- Copy SVG to clipboard.
- Export current selection or full document.
- Set artboard to source size, content bounds or custom bounds.
- Choose decimal precision.
- Optionally optimise IDs and remove editor metadata.
- Preserve groups when useful.
- Preview export size and element count.

### Project files

- Save as a native `.fekthor` package.
- Store source image, settings, intermediate masks, vector document and edit history checkpoint.
- Reopen without re-running the entire pipeline.
- Mark projects as dirty when settings or geometry change.
- Autosave using native document behaviour.

## Version 1

Version 1 turns the MVP into a dependable production tool.

### Better stroke reconstruction

- Variable-width stroke profiles.
- Width smoothing along a path.
- Tapered endpoints.
- Junction-aware width handling.
- Detection of intentionally doubled or parallel strokes.
- Better treatment of touching filled regions and outlines.
- Closed-loop centreline recovery.
- Endpoint snapping and continuation suggestions.

### Better preprocessing

- Local adaptive thresholding.
- Uneven-paper and shadow correction.
- Deskew and perspective correction for scans.
- Dust and scratch cleanup.
- Colour clustering for flat artwork.
- Transparent-background recovery.
- Edge-preserving upscaling for low-resolution sources.

### Quality inspection

- Difference heatmap.
- Edge-distance overlay.
- Highlight likely topology errors.
- Show unresolved tiny components.
- Show paths with unusually high node density.
- Report total paths, nodes, fills and estimated SVG size.
- Compare current result against previous settings.

### Editing improvements

- Layers and groups.
- Multi-select and alignment.
- Distribute and mirror.
- Snap to endpoints, guides and pixel grid.
- Pen tool for small repairs.
- Eraser and scissors tools.
- Local smoothing brush.
- Local width brush.
- Replace a bad section while preserving the rest of a path.
- Convert Stroke to Outline and Outline to Stroke where possible.

### Presets

- Clean line art.
- Scanned ink.
- Pencil sketch.
- Icon.
- Signature.
- Flat logo.
- Colouring page.
- Technical diagram.
- User-defined presets.
- Preset import and export.

### Batch processing

- Process a folder or multiple files.
- Apply a preset.
- Preview a representative sample.
- Export to a destination folder.
- Continue after individual failures.
- Produce a conversion report.

### Command line interface

- Headless conversion using the same Rust core.
- JSON configuration.
- Deterministic exit codes.
- SVG and diagnostic output.
- Useful for CI, asset pipelines and bulk conversion.

### Additional export options

- Simplified SVG for web.
- Editable SVG retaining groups and metadata.
- Plain SVG paths without project metadata.
- EPS if a reliable exporter is available.
- DXF for simple line geometry, explicitly without CAD guarantees.
- PNG preview rendered from vectors.

## AI-assisted features

AI features remain optional and clearly identified.

### Classification assistance

- Predict Stroke, Fill, Texture, Text or Ignore for ambiguous regions.
- Detect likely object boundaries when components touch.
- Suggest whether nearby segments belong to the same stroke.

### Repair assistance

- Suggest continuation across a small occlusion.
- Repair a broken contour.
- Remove compression artefacts while preserving intended geometry.
- Infer a cleaner local curve from neighbouring context.
- Show the proposed change before applying it.

### Clean redraw

- Redraw with adjustable faithfulness.
- Regularise hand-drawn shapes.
- Normalise stroke consistency.
- Preserve the original as a separate reference layer.
- Never overwrite the faithful vector result without confirmation.

## Later possibilities

- iPad application with Apple Pencil correction tools.
- Windows application using the same engine.
- Plugin or extension for design tools.
- Public SDK for centreline and hybrid vectorisation.
- WebAssembly build for local browser processing.
- Animation-friendly path ordering.
- Semantic recognition of common icons and geometric primitives.
- Text recognition with optional replacement by live text.
- Constraint detection for circles, rectangles, symmetry and repeated forms.
- Collaborative review, only if it can remain optional.

## Deliberately excluded features

The following should not be added merely to appear competitive:

- Mandatory account creation.
- Cloud-only conversion.
- Token or credit systems for ordinary tracing.
- Social feeds or community templates.
- A full illustration suite before tracing quality is established.
- Automatic generative changes inside faithful mode.
- Export formats that flatten all real strokes into filled outlines by default.

## MVP acceptance criteria

The MVP is accepted when:

1. A clean monochrome illustration can be imported, vectorised and exported without network access.
2. Smart mode emits both real strokes and filled shapes in the same SVG.
3. A user can correct a wrong Stroke/Fill decision locally without restarting the complete document.
4. The vector result can be overlaid on the source and inspected at high zoom.
5. SVG output reopens correctly in browsers and at least two mainstream vector editors.
6. Undo and redo cover automatic settings, classification changes and manual path edits.
7. Benchmark tests verify deterministic output and prevent geometry regressions.

# User experience

## Design direction

Fekthor should be a calm native utility, not a dense illustration suite. The workspace should prioritise the image and the comparison between source and vector. Controls should appear in context, use plain language and avoid exposing every algorithm parameter by default.

The application should open directly into an empty canvas with one clear action: open or drop an image.

## Window structure

The main window has four stable regions:

1. **Toolbar** — document actions, view mode, vectorisation mode and export.
2. **Canvas** — source and vector preview with direct manipulation.
3. **Inspector** — contextual settings for the document, current mode or current selection.
4. **Status bar** — zoom, processing state, path count, node count and warnings.

The inspector should be collapsible. The canvas should remain the visual centre of the application.

## Empty state

The empty state contains:

- A large drop target.
- An **Open Image** button.
- A short explanation: “Turn line art and flat images into editable strokes and shapes.”
- A small list of supported source types.
- Recent projects below the primary action, only when available.

There should be no dashboard, account prompt or tutorial carousel before the user can open an image.

## Main toolbar

Suggested left-to-right structure:

- Sidebar/inspector toggle.
- Open.
- Save.
- Undo and redo.
- Selection/edit tool group.
- View selector: Source, Vector, Split, Overlay, Difference.
- Mode selector: Smart, Strokes, Shapes.
- Process or Update button when automatic live processing is disabled.
- Export.

Controls that change geometry should not be mixed with view-only controls.

## First import

After import, Fekthor immediately runs a fast analysis preview. The interface should show progressive states rather than a blocking modal:

1. Preparing image.
2. Separating foreground.
3. Detecting strokes and shapes.
4. Fitting curves.
5. Comparing result.

The user can inspect the source while processing continues. A cancel action remains available.

When analysis finishes, Smart mode is selected and the inspector shows only the primary controls.

## Primary inspector

### Vectorise section

- Mode: Smart / Strokes / Shapes.
- Preset.
- Detail.
- Smoothness.
- Noise removal.
- Gap repair.
- Classification bias, visible in Smart mode only.
- Stroke width: Auto / Fixed.

Each control should include a compact visual explanation or tooltip. Values should be reversible and should update a low-resolution preview quickly.

### Result section

- Paths.
- Nodes.
- Strokes.
- Fills.
- Uncertain regions.
- Estimated SVG size.

Warnings should be actionable. Selecting “3 uncertain regions” should navigate through them.

### Export section

A compact summary of the active export preset and artboard. Full export options belong in the export sheet.

## Canvas comparison modes

### Source

Shows only the original or preprocessed raster.

### Vector

Shows only the generated vector result against a configurable background.

### Split

Uses a draggable divider. The left side shows source and the right side shows vector. The divider should be easy to grab without obscuring the image.

### Overlay

Shows both layers with an opacity control. The vector layer can use its actual colours or a temporary inspection colour.

### Difference

Shows visual error between the rendered vector and the cleaned source. It must include a monochrome or patterned option so information is not communicated through colour alone.

Keyboard shortcuts should switch these views quickly.

## Selection behaviour

Clicking a region selects the generated element and highlights the raster pixels that contributed to it. The inspector then changes from global settings to element settings.

For a stroke, show:

- Classification and confidence.
- Stroke width or width profile.
- Colour.
- Cap and join.
- Open/closed state.
- Node count.
- Simplify action.
- Convert to Fill.
- Ignore region.

For a fill, show:

- Classification and confidence.
- Fill colour.
- Hole count.
- Node count.
- Simplify action.
- Convert to Stroke.
- Ignore region.

For an uncertain region, place the classification choice first and show the source crop beside the generated interpretation.

## Correcting classification

A wrong classification should be fixable with one direct action:

- **Make Stroke**
- **Make Fill**
- **Ignore**
- **Use Automatic**

The selected region should recompute locally. The rest of the document must remain visually stable.

Multi-selection should allow changing several similar regions at once.

## Topology correction tools

These tools appear only when needed:

### Cut

Draw a short line across an incorrectly joined raster region. Fekthor separates the mask and recomputes the affected vectors.

### Join

Select two endpoints. Fekthor previews a connection and applies it after confirmation.

### Erase noise

Brush over unwanted source pixels. This edits a non-destructive cleanup mask rather than the original image.

### Restore

Brush source pixels back into the cleanup mask.

### Local smooth

Brush over a rough vector section to refit only that range.

These correction tools operate on the relationship between raster evidence and vector geometry, not merely on final paths.

## Node editing

Node editing should remain available but secondary. Most users should correct the source interpretation rather than manually rebuilding paths.

When enabled:

- Nodes appear only for selected paths.
- Smooth and corner nodes are visually distinct.
- Handles appear on selection.
- Double-click adds a node.
- Delete removes a node while refitting adjacent segments.
- Dragging an endpoint offers snapping to nearby compatible endpoints.
- A before/after preview is available for simplify operations.

## Export sheet

The export sheet contains:

### Format

- SVG.
- PDF.
- PNG preview.
- Additional formats only when implemented reliably.

### SVG structure

- Editable.
- Optimised for web.
- Plain paths.
- Preserve element IDs.
- Preserve groups.
- Decimal precision.

### Artboard

- Source bounds.
- Content bounds.
- Selection bounds.
- Custom size and padding.

### Appearance

- Preserve original colours.
- Override stroke colour.
- Override fill colour.
- Transparent or coloured background for raster preview exports.

The sheet displays an estimated file size and a small structural summary before export.

## Project browser

Fekthor does not need a dashboard. Native recent-document behaviour is sufficient. A lightweight recent-project view may appear in the empty state, with thumbnail, filename and last-opened date.

## Preferences

Preferences should remain limited:

- Default vectorisation preset.
- Live preview on/off.
- Preview quality.
- Default SVG export preset.
- Checkerboard/background appearance.
- Optional diagnostics.
- Optional anonymous diagnostics, off by default.
- Downloaded model management when ML features exist.

## Keyboard commands

Suggested defaults:

- `⌘O` Open.
- `⌘S` Save.
- `⇧⌘S` Save As.
- `⌘E` Export.
- `⌘Z` Undo.
- `⇧⌘Z` Redo.
- `1` Source view.
- `2` Vector view.
- `3` Split view.
- `4` Overlay view.
- `5` Difference view.
- `V` Selection tool.
- `A` Node tool.
- `C` Cut region tool.
- `J` Join endpoints.
- `F` Fit document.
- `0` Actual size.
- `Tab` Hide or show inspector.
- `[` and `]` Previous and next uncertain region.

Shortcuts should avoid conflicts with standard macOS document commands and remain customisable later.

## Error handling

Errors should appear near the relevant operation and preserve the current document.

Examples:

- Unsupported or corrupt image: explain that the file could not be decoded.
- Too-large image: offer a preview-size import or continue with a memory warning.
- Failed region processing: retain the previous result and mark the region.
- Export incompatibility: identify the unsupported element and offer a conversion option.

Never discard the existing result because a new processing attempt failed.

## Accessibility

- Full keyboard navigation and visible focus.
- VoiceOver labels for canvas controls and inspector values.
- Commands available through menus, not only icons.
- Minimum target sizes suitable for motor accessibility.
- Difference patterns in addition to colour.
- Respect Reduce Motion and Increase Contrast.
- Avoid transient controls that disappear before they can be reached.

## Native behaviour

The app should use standard macOS conventions where they reduce learning:

- Document-based windows.
- Native open, save and autosave behaviour.
- Quick Look preview for `.fekthor` projects later.
- Standard menu commands.
- Drag and drop to Finder and compatible vector editors where practical.
- Copy SVG and selected paths through the clipboard.

The application should look specific to its task, but not invent a custom windowing or document model without a clear benefit.

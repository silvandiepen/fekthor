# Product plan

## Vision

Fekthor turns raster artwork into compact, editable vector documents while preserving the visual intent of the source. It is designed for cases where conventional image tracing gives technically valid SVG files that are structurally wrong: outlines become thick filled contours, strokes are duplicated, intersections become messy and the result contains far too many nodes.

The application should feel less like a filter and more like a careful reconstruction tool. It should infer whether a visual element represents a stroke or a filled region, expose that decision to the user and make corrections inexpensive.

## Product statement

For illustrators, designers, developers, educators and small studios who need editable vectors from existing raster art, Fekthor provides faithful centreline and hybrid vectorisation with a calm native workflow. Unlike standard outline tracers or generative redraw tools, it preserves real strokes, keeps fills as fills and does not silently redesign the artwork.

## Primary jobs to be done

1. Convert clean black-and-white line art into SVG paths with editable stroke width.
2. Convert mixed line art containing solid details into a hybrid document of strokes and fills.
3. Recover usable vectors from scans, screenshots and moderately compressed images.
4. Produce a low-complexity SVG suitable for further editing, animation, web use or print.
5. Compare the vector result against the source and correct only the ambiguous parts.
6. Export predictable, standards-based files without cloud processing.

## Target users

### Independent illustrators and designers

They receive PNG or JPEG artwork but need an editable SVG, PDF or EPS-like vector document. They care about smooth curves, low node count and preserving the character of the original drawing.

### UI and icon designers

They need to reconstruct icons, pictograms and monochrome assets. They care about precise geometry, consistent stroke width, snapping and compact SVG output.

### Developers

They need vectors for web interfaces, animation, canvas rendering, game assets or icon systems. They care about deterministic output, clean SVG structure and batch processing.

### Educators and content creators

They convert colouring pages, worksheets and hand-drawn learning materials into scalable assets. They need a simple workflow and reliable results without learning a full vector editor.

### Archives and small studios

They digitise historical line drawings, logos, signatures and diagrams. They care about fidelity, repeatability and local processing.

## Supported source categories

The initial product should explicitly optimise for:

- High-contrast black-and-white line art.
- Scanned pencil, pen and marker drawings after cleanup.
- Cartoon and colouring-page illustrations.
- Icons, symbols and simple logos.
- Signatures and handwriting.
- Diagrams and technical line drawings without strict CAD semantics.
- Flat-colour artwork with a limited palette.

Later versions may support:

- Variable-width calligraphy.
- Textured brushes.
- Complex multi-colour illustrations.
- Photos converted into stylised vector artwork.

## Product modes

### Smart

The default mode. Fekthor separates the source into meaningful regions and classifies each as a stroke, fill or uncertain element. It then combines centreline extraction and contour tracing into one editable document.

Smart mode is successful when a typical clean line-art image produces a useful result without requiring the user to understand the underlying algorithms.

### Strokes

For drawings where dark pixels represent ink lines. The engine reconstructs centreline paths, estimates width and emits SVG strokes with editable caps and joins.

The user may choose constant-width or variable-width output. Constant-width output is the MVP default because it is simpler and broadly editable.

### Shapes

For silhouettes, logos and flat graphic regions. The engine traces contours into closed filled paths, simplifies them and preserves holes and nesting.

### Clean redraw

An optional, explicitly generative mode. It may regularise inconsistent curves, repair missing sections or redraw at a chosen visual cleanliness level. It must never be confused with faithful vectorisation and must show that geometry may change.

## Core workflow

1. The user drops or opens an image.
2. Fekthor analyses it and presents a Smart result.
3. The user compares source and vector using split, overlay or difference views.
4. Ambiguous regions are highlighted rather than hidden.
5. The user selects a region and changes it between Stroke, Fill or Ignore when necessary.
6. The user adjusts a small set of global controls: detail, smoothing, noise removal and stroke behaviour.
7. The user optionally edits individual paths or junctions.
8. The result is exported as SVG or PDF, or saved as a Fekthor project for later work.

## Product requirements

### Faithfulness

- The default pipeline must not invent objects or substantially alter proportions.
- Re-rendered vectors should visually match the cleaned source at normal viewing size.
- The application must retain the original image for comparison.
- Every automatic cleanup should be reversible.

### Editability

- Stroke-like regions must be represented as actual stroked paths where practical.
- Filled regions must remain closed filled shapes.
- Paths should contain as few control points as possible without materially reducing fidelity.
- Groups, layers and source-region relationships should be preserved internally.
- SVG output should be readable and compatible with mainstream vector editors and browsers.

### Predictability

- The same input and settings must produce the same output.
- Presets must be explicit and versioned.
- Export must not depend on network availability.
- The user should be able to inspect why a region became a stroke or fill.

### Performance

- A clean 2048 × 2048 monochrome illustration should produce an initial preview within a few seconds on a contemporary Mac.
- Parameter changes should reuse intermediate results rather than restart the entire pipeline.
- Long operations must be cancellable.
- Large images may be downsampled for preview while final processing uses the original resolution.

### Accessibility

- All commands must be reachable by keyboard.
- Controls must expose accessible names, values and help text.
- Difference views must not rely on colour alone.
- The interface must support system text sizing and reduced motion.

## Non-goals for the first release

- Replacing Illustrator, Affinity Designer or a complete vector editor.
- Full photo vectorisation.
- Automatic font creation.
- CAD-grade dimensioning or geometric constraints.
- Perfect semantic object recognition.
- Cloud collaboration or account systems.
- Hidden generative enhancement in the normal vectorisation pipeline.
- Supporting every historical vector format.

## Differentiation

Fekthor is not simply another threshold-and-trace utility. Its differentiation is the combination of:

- Centreline reconstruction with real stroke semantics.
- Automatic hybrid classification of strokes and fills.
- Topology-aware junction handling.
- Visible confidence and local correction.
- Render-back comparison against the source.
- A compact, native workflow focused on conversion rather than general illustration.

## Success metrics

### Output quality

- Percentage of benchmark images that produce a usable result without manual path editing.
- Render similarity between the generated vector and the cleaned raster source.
- Topology correctness: preserved connected components, holes, endpoints and junctions.
- Reduction in path and node count compared with conventional outline tracing.
- Accuracy of stroke-versus-fill classification.

### User efficiency

- Median time from import to export.
- Number of manual corrections per image.
- Percentage of sessions completed using Smart mode.
- Undo frequency after automatic operations.

### Reliability

- Crash-free sessions.
- Successful export rate.
- Deterministic golden-test pass rate.
- Peak memory and processing time across benchmark sizes.

## Commercial shape

The initial product should work as a paid, offline-first macOS application. No account should be required. Core deterministic vectorisation should be included in the application rather than metered per conversion.

Potential later extensions include a command-line tool, an SDK, batch automation, an iPad companion and optional downloadable ML models. These should not complicate the first product before the core tracing quality is proven.

## Release definition

The first public release is ready when a user can import common raster formats, generate Smart/Stroke/Shape results, inspect and correct classification, perform basic path cleanup, save a project and export a compact SVG and PDF with reliable visual fidelity.

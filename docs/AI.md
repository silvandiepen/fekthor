# AI and model strategy

## Position

AI may improve Fekthor, but it should not be the foundation of faithful vectorisation. The core product must be able to reconstruct useful vectors through deterministic image processing and geometry. A generative model can easily produce a cleaner-looking image while quietly changing proportions, intersections or character details.

Fekthor therefore separates two promises:

- **Faithful vectorise** reconstructs the source as accurately and deterministically as possible.
- **Clean redraw** may reinterpret the source and is clearly marked as generative.

## Useful roles for machine learning

### Region classification

A small model can classify regions or patches as:

- Stroke.
- Fill.
- Texture.
- Text.
- Background.
- Uncertain.

The model output remains one signal among geometric features. The user can inspect and override the result.

### Stroke continuation

A model can score whether two nearby endpoints likely belong to the same original stroke. Geometry remains responsible for constructing the actual connection.

### Occlusion repair

When a line is hidden by a small object or scan defect, a model may propose a continuation. The proposal must be shown before application and stored as an explicit edit.

### Cleanup

A model may predict a clean foreground mask from a noisy scan. The source image and deterministic cleanup path must remain available for comparison.

### Primitive and structure recognition

Later models may detect likely circles, rectangles, symmetry, repeated forms or text. Recognition should create editable constraints or suggestions rather than replacing geometry without review.

## Where AI should not be used by default

- Silently redrawing complete images.
- Guessing missing large regions.
- Changing facial expressions or object proportions.
- Flattening unusual hand-drawn details into generic shapes.
- Sending user images to a server without a specific, informed action.
- Making ordinary vectorisation dependent on model availability.

## Initial model approach

The first ML experiment should be a compact patch or region classifier that runs on device. It should consume both raster evidence and deterministic geometric measurements.

Possible inputs:

- Normalised region crop.
- Foreground mask crop.
- Distance-transform crop.
- Region area and perimeter.
- Width median and variance.
- Skeleton length.
- Endpoint and junction counts.
- Hole count.
- Contour complexity versus centreline complexity.

Outputs:

- Class probabilities.
- Confidence calibration value.
- Optional embedding for grouping similar regions.

The deterministic classifier remains the baseline and fallback.

## Training data

A useful dataset needs ground truth that describes vector semantics, not merely raster masks.

Each sample should contain:

- Source raster.
- Clean foreground or colour segmentation.
- Ground-truth vector document.
- Stroke/fill classification per element.
- Centreline paths.
- Stroke widths or width profiles.
- Filled contours and holes.
- Junction and endpoint annotations.
- Source-to-vector rendering parameters.

## Dataset sources

### Synthetic data

Synthetic generation is valuable because perfect ground truth is available.

Generate random documents containing:

- Open and closed Bézier strokes.
- Constant and variable widths.
- Different caps and joins.
- Crossings and branches.
- Filled circles, blobs and silhouettes.
- Filled shapes with outlines.
- Multiple flat colours.
- Controlled blur, antialiasing, downsampling and compression.
- Paper texture, scan shadows and small gaps.

Render at multiple sizes and preserve the original vector document as ground truth.

Synthetic data should include imperfect hand-drawn geometry rather than only clean mathematical curves.

### Curated real data

Real illustrations are needed because synthetic degradation cannot represent every scan and drawing style. Their vectors must be created or corrected manually under an appropriate licence.

Do not train on arbitrary online artwork merely because it is publicly visible.

### User-contributed corrections

A later opt-in programme could collect anonymised source crops and corrected classifications. It must be disabled by default and explain exactly what is uploaded.

## Evaluation

Model accuracy alone is insufficient. Evaluate end-to-end impact.

Metrics include:

- Stroke/fill classification accuracy and F1 by class.
- Calibration: whether an 80% confidence prediction is correct about 80% of the time.
- Reduction in manual classification corrections.
- Change in render similarity.
- Change in topology errors.
- False confident predictions.
- Runtime and memory.
- Behaviour across drawing styles and source resolutions.

A model should only ship when it improves benchmark and user-correction results over deterministic rules.

## Confidence and uncertainty

The UI should not treat every model prediction equally. Confidence must be calibrated and mapped to behaviour:

- High confidence: apply automatically in Smart mode.
- Medium confidence: apply but mark for review.
- Low confidence: preserve as Uncertain and request a user decision when relevant.

Confidence should be stored in the project so later engine versions can explain differences.

## Clean redraw mode

Clean redraw is a separate optional pipeline. It may use a generative image or vector model to produce a simplified interpretation.

Required safeguards:

- The mode is explicitly named and described as interpretive.
- The faithful result remains available.
- The user controls faithfulness and cleanup strength.
- The output appears as a new version or layer.
- Before/after comparison is mandatory.
- The app must not claim pixel-faithful reconstruction.

A possible pipeline is:

1. Produce a faithful vector or cleaned raster.
2. Ask a model for a cleaned structural proposal.
3. Convert the proposal into Fekthor’s internal vector model.
4. Render it back and show differences.
5. Let the user accept selected regions rather than only the complete redraw.

## Deployment

### On-device first

Preferred deployment options:

- Core ML for macOS-specific models.
- ONNX Runtime or a Rust-compatible inference runtime if cross-platform reuse is required.
- Quantised models to reduce application size and memory.
- Downloadable optional model packages rather than inflating the base application indefinitely.

### Cloud models

Cloud processing may be offered later for computationally heavy redraw features, but only as an explicit action. The application must show:

- What data leaves the device.
- Which provider processes it.
- Whether data is retained.
- Expected cost or quota.
- Whether the result is generative.

Core vectorisation should never require cloud access.

## Model versioning

Projects should record:

- Model identifier.
- Model version.
- Class schema version.
- Confidence calibration version.
- Relevant preprocessing version.

A project should retain its existing result when a model is upgraded. Reprocessing should be a user-controlled action.

## Failure handling

When a model fails or is unavailable:

- Fall back to deterministic classification.
- Preserve existing results.
- Mark model-dependent suggestions as unavailable.
- Never block export of already generated vectors.

## Research questions

1. Does a learned region classifier materially outperform width- and topology-based rules?
2. Is a patch model sufficient, or is whole-image context needed for ambiguous solid marks?
3. Can a model predict stroke pairing at junctions without changing visible geometry?
4. Can segmentation models clean noisy scans without erasing small intended details?
5. Does a differentiable vector renderer improve curve fitting enough to justify its complexity?
6. Can model suggestions reduce correction time while remaining transparent and deterministic after acceptance?

## Shipping rule

No AI component should be added because it sounds marketable. It must improve a measured failure mode, remain inspectable and preserve an offline deterministic path through the product.

# Privacy and security

## Default posture

Fekthor should process images locally and require no account. Import, vectorisation, project saving and export must function without network access.

The application may later offer optional model downloads, update checks or cloud-assisted redraw features. These must remain separate from ordinary vectorisation and must not weaken the offline default.

## User data handled by the app

Fekthor may process or store:

- Imported raster images.
- Generated vector geometry.
- Preprocessing masks and diagnostics.
- Project settings and user edits.
- Thumbnails and recent-document metadata.
- Optional performance or crash diagnostics when enabled.
- Optional cloud requests initiated by the user in future features.

Images may contain private artwork, signatures, documents or identifiable material. Treat all imported content as sensitive user data even when the application cannot interpret it semantically.

## Local processing requirements

- Core vectorisation must not initiate network requests.
- The engine must not depend on a remote model or licence server for normal operation.
- Temporary processing files should remain inside the app container or project package.
- Temporary files should be removed after use when they are no longer needed.
- Project caches must not be written to publicly accessible locations.
- Clipboard content should only be read after an explicit paste or import action.

## File access

The macOS application should use sandbox-compatible file access.

- Open only files selected by the user or received through drag and drop.
- Use security-scoped bookmarks only when linked-source projects require persistent access.
- Prefer embedding the source in the `.fekthor` package so projects remain portable.
- Explain when a project links to an external source rather than embedding it.
- Do not scan image libraries or folders without an explicit batch-processing selection.

## Project sharing

A `.fekthor` package may contain:

- The complete original image.
- Cleanup masks.
- Generated geometry.
- Diagnostic metadata.
- A preview thumbnail.

The share/export interface should distinguish:

- **Share project** — includes source and editable project information.
- **Export vector** — includes only the selected vector output and permitted metadata.

Optimised SVG and PDF exports must not embed the original raster unless the user explicitly selects a reference-image option.

## Diagnostics and telemetry

Telemetry should be absent or opt-in.

If diagnostics are introduced:

- The preference is off by default.
- Describe collected fields in plain language.
- Do not upload source images, masks, vector paths or filenames.
- Avoid persistent device identifiers.
- Allow the user to inspect or export a diagnostic report before sharing it.
- Provide a direct way to disable future collection.

Crash reports may contain memory or path information. Use platform crash reporting carefully and document what is transmitted.

## Optional AI models

### On-device models

- Model packages should be signed or integrity-checked.
- Record model version and checksum.
- Store downloaded models in the application container.
- Allow removal from Preferences.
- Continue functioning with deterministic rules when the model is absent or corrupt.

### Cloud-assisted features

A future cloud action must present:

- That the image or selected crop will leave the device.
- Which service or provider will receive it.
- Whether the operation is faithful analysis or generative redraw.
- Applicable retention terms.
- Expected cost or quota.
- A clear Cancel action before upload.

Cloud processing should use only the minimum required image region when the task is local. Do not upload the complete project when a selected crop is sufficient.

## Secrets

The application should not ship provider secrets inside the client.

Possible future approaches:

- User-supplied API keys stored in Keychain.
- A controlled backend issuing short-lived tokens.
- Platform entitlement-based services.

Never store raw API keys in project files, preferences plist files or logs.

## Input validation

Image and project files are untrusted input.

The app and engine must:

- Enforce maximum dimensions and allocation limits.
- Validate decoded row strides and buffer lengths.
- Reject non-finite geometry values.
- Guard against decompression bombs.
- Validate package paths and reject path traversal.
- Treat cache files as disposable and untrusted.
- Parse JSON with size and nesting limits.
- Fail safely on corrupt or unsupported project versions.

A corrupt region or cache should not cause unsafe memory access or overwrite unrelated files.

## Native bridge safety

The Swift/Rust boundary should:

- Use explicit ownership rules.
- Validate pointer and buffer lengths.
- Avoid exposing internal mutable pointers to Swift.
- Convert panics into structured errors at the boundary.
- Support cancellation without freeing memory still in use.
- Include fuzz and stress tests for bridge DTO decoding.

## Export safety

SVG is XML-based and may be consumed by other applications.

Fekthor-generated SVG should:

- Avoid scripts.
- Avoid external resource references by default.
- Avoid event-handler attributes.
- Escape IDs and metadata.
- Use known-safe numeric and colour formats.
- Include only Fekthor metadata selected by the export preset.

When importing SVG becomes a feature, imported SVG must be treated as active untrusted content and sanitised before preview.

## Logs

Development logs may contain:

- File paths.
- Region coordinates.
- Engine settings.
- Timing data.

Production logging should minimise these details. Do not log image bytes, SVG content or model request payloads. Diagnostic bundles should make sensitive fields visible to the user before sharing where practical.

## Dependency security

- Pin dependency versions through lockfiles.
- Review native libraries and their transitive dependencies.
- Run vulnerability checks in CI.
- Verify licences before distribution.
- Avoid executing external tracing binaries from writable or uncontrolled paths.
- Prefer library integration over shell invocation when it improves isolation and predictability.

## Update integrity

Distribution should use Apple signing and notarisation. Any separate model or preset downloads should use HTTPS and integrity validation. The app must reject a package whose checksum or signature does not match.

## Data deletion

Because no account is required, deletion is primarily local:

- Projects are ordinary user files.
- Caches can be cleared from Preferences.
- Downloaded models can be removed.
- Optional diagnostic history can be cleared.
- Removing the app should not delete user-created project files outside the container without an explicit action.

## Threat model summary

Primary threats include:

- Malformed image or project files causing excessive allocation or crashes.
- Unsafe native bridge behaviour.
- Accidental inclusion of private source images in shared exports.
- Hidden network transmission by optional services.
- Dependency or model-package tampering.
- SVG output containing unsafe external or executable content.

The product does not initially require authentication, collaborative permissions or server-side storage, which substantially limits the attack surface.

## Release requirements

Before release:

- Verify complete core workflow with network disabled.
- Audit all outbound network requests.
- Inspect project and export packages for accidental source inclusion.
- Test malformed and oversized inputs.
- Verify app sandbox entitlements.
- Review dependency licences and vulnerabilities.
- Publish an accurate privacy statement based on implemented behaviour, not planned behaviour.

//! Fekthor core engine.
//!
//! Deterministic raster-to-vector pipeline. The engine is UI-free and testable
//! without macOS; see `docs/ARCHITECTURE.md`. This crate currently implements the
//! Shapes (flat fill) conversion mode plus render-back comparison; Strokes and
//! Gradient modes follow.

pub mod color;
pub mod compare;
pub mod contour;
pub mod document;
pub mod geom;
pub mod raster;
pub mod render;
pub mod shapes;
pub mod svg;

/// A conversion mode. Each mode reconstructs different drawing semantics.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Mode {
    /// Flat filled shapes with no strokes (colour-region tracing).
    Shapes,
    /// Centreline strokes for line art (skeleton reconstruction).
    Strokes,
    /// Filled shapes with fitted gradients for shaded / 3D-style art.
    Gradient,
}

/// Structured engine error. The engine never panics across a host boundary.
#[derive(Debug)]
pub enum EngineError {
    Io(String),
    Decode(String),
    Render(String),
    Unsupported(String),
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EngineError::Io(m) => write!(f, "io error: {m}"),
            EngineError::Decode(m) => write!(f, "decode error: {m}"),
            EngineError::Render(m) => write!(f, "render error: {m}"),
            EngineError::Unsupported(m) => write!(f, "unsupported: {m}"),
        }
    }
}

impl std::error::Error for EngineError {}

pub type Result<T> = std::result::Result<T, EngineError>;

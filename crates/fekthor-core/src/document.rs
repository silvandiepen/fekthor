//! Internal vector document (subset).
//!
//! Richer than exported SVG; see `docs/DOCUMENT-MODEL.md`. This is an initial
//! subset covering filled shapes and stroked paths with stable IDs.

use crate::geom::Point;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone)]
pub struct VectorDocument {
    pub width: u32,
    pub height: u32,
    pub elements: Vec<Element>,
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(tag = "type", rename_all = "kebab-case")]
pub enum Element {
    Fill(FillShape),
    Stroke(StrokePath),
}

/// A filled region. `rings[0]` is the outer contour; the remainder are holes.
/// Rendered with the even-odd fill rule.
#[derive(Serialize, Deserialize, Clone)]
pub struct FillShape {
    pub id: String,
    pub color: [u8; 3],
    pub rings: Vec<Vec<Point>>,
}

/// A stroked centreline path (constant width for the MVP).
#[derive(Serialize, Deserialize, Clone)]
pub struct StrokePath {
    pub id: String,
    pub color: [u8; 3],
    pub width: f64,
    pub closed: bool,
    /// Ordered points; the exporter fits/emits a smooth path through them.
    pub points: Vec<Point>,
}

impl VectorDocument {
    pub fn new(width: u32, height: u32) -> Self {
        VectorDocument {
            width,
            height,
            elements: Vec::new(),
        }
    }

    pub fn fill_count(&self) -> usize {
        self.elements
            .iter()
            .filter(|e| matches!(e, Element::Fill(_)))
            .count()
    }

    pub fn stroke_count(&self) -> usize {
        self.elements
            .iter()
            .filter(|e| matches!(e, Element::Stroke(_)))
            .count()
    }

    pub fn node_count(&self) -> usize {
        self.elements
            .iter()
            .map(|e| match e {
                Element::Fill(f) => f.rings.iter().map(|r| r.len()).sum::<usize>(),
                Element::Stroke(s) => s.points.len(),
            })
            .sum()
    }
}

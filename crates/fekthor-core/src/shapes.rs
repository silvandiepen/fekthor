//! Shapes (flat fill) conversion mode.
//!
//! Colour-quantize the source, trace each colour region into filled contours,
//! simplify, and assemble a back-to-front filled document. No strokes are
//! emitted (D-002: genuinely solid content becomes filled shapes).

use crate::color::quantize;
use crate::contour::regions;
use crate::document::{Element, FillShape, VectorDocument};
use crate::geom::{area, simplify_closed};
use crate::raster::RgbaImage;

pub struct ShapesConfig {
    /// Target palette size.
    pub colors: usize,
    /// Lloyd iterations for quantization.
    pub iters: usize,
    /// Douglas-Peucker tolerance in source pixels.
    pub epsilon: f64,
    /// Minimum region/hole area in pixels; smaller are dropped as noise.
    pub min_area: f64,
}

impl Default for ShapesConfig {
    fn default() -> Self {
        ShapesConfig {
            colors: 16,
            iters: 8,
            epsilon: 1.0,
            min_area: 6.0,
        }
    }
}

pub fn run(img: &RgbaImage, cfg: &ShapesConfig) -> VectorDocument {
    let q = quantize(img, cfg.colors, cfg.iters);
    let mut regs = regions(&q);
    // Paint back-to-front: larger regions first so smaller ones layer on top.
    // Stable tie-break by palette index then first-point keeps output deterministic.
    regs.sort_by(|a, b| {
        b.area
            .partial_cmp(&a.area)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.palette_idx.cmp(&b.palette_idx))
    });

    let mut doc = VectorDocument::new(img.width, img.height);
    let mut next_id = 0usize;
    for r in &regs {
        if r.area < cfg.min_area {
            continue;
        }
        let outer = simplify_closed(&r.outer, cfg.epsilon);
        if outer.len() < 3 {
            continue;
        }
        let mut rings = vec![outer];
        for hole in &r.holes {
            if area(hole) < cfg.min_area {
                continue;
            }
            let hs = simplify_closed(hole, cfg.epsilon);
            if hs.len() >= 3 {
                rings.push(hs);
            }
        }
        let color = q.palette[r.palette_idx as usize];
        doc.elements.push(Element::Fill(FillShape {
            id: format!("fill-{next_id}"),
            color,
            rings,
        }));
        next_id += 1;
    }
    doc
}

//! Colour-region contour extraction.
//!
//! For each palette index a binary mask is built and its outer contours and
//! holes are traced (Suzuki-Abe via `imageproc`), grouped into fillable regions.

use crate::color::Quantized;
use crate::geom::{area, Point};
use image::{GrayImage, Luma};
use imageproc::contours::{find_contours, BorderType};

/// A single fillable region: one outer ring with zero or more holes.
pub struct Region {
    pub palette_idx: u16,
    pub outer: Vec<Point>,
    pub holes: Vec<Vec<Point>>,
    pub area: f64,
}

/// Extract all fillable regions across every palette index.
pub fn regions(q: &Quantized) -> Vec<Region> {
    let w = q.width;
    let h = q.height;
    let mut out = Vec::new();

    for idx in 0..q.palette.len() as u16 {
        // Pad by 1px so regions touching the image border are traced correctly
        // (Suzuki-Abe needs a zero border); points are offset back by -1.
        let mut mask = GrayImage::new(w + 2, h + 2);
        let mut any = false;
        for y in 0..h {
            for x in 0..w {
                if q.indices[(y * w + x) as usize] == idx {
                    mask.put_pixel(x + 1, y + 1, Luma([255]));
                    any = true;
                }
            }
        }
        if !any {
            continue;
        }
        let to_pt = |p: &imageproc::point::Point<i32>| [(p.x - 1) as f64, (p.y - 1) as f64];

        let contours = find_contours::<i32>(&mask);
        // Map outer-contour vec-index -> position in a per-index Region list.
        for (ci, c) in contours.iter().enumerate() {
            if c.border_type != BorderType::Outer {
                continue;
            }
            let outer: Vec<Point> = c.points.iter().map(to_pt).collect();
            if outer.len() < 3 {
                continue;
            }
            let mut holes = Vec::new();
            for other in &contours {
                if other.border_type == BorderType::Hole && other.parent == Some(ci) {
                    let ring: Vec<Point> = other.points.iter().map(to_pt).collect();
                    if ring.len() >= 3 {
                        holes.push(ring);
                    }
                }
            }
            let a = area(&outer);
            out.push(Region {
                palette_idx: idx,
                outer,
                holes,
                area: a,
            });
        }
    }

    out
}

//! Render-back: rasterize exported SVG with resvg for comparison.
//!
//! This is the engine-neutral reference renderer used to validate that the
//! exported vector actually reproduces the source (docs/ARCHITECTURE.md O-003).

use crate::raster::RgbaImage;
use crate::{EngineError, Result};
use resvg::tiny_skia::{Pixmap, Transform};
use resvg::usvg::{Options, Tree};

/// Render an SVG string to an RGBA buffer of the given size over a white base.
pub fn render_svg(svg: &str, width: u32, height: u32) -> Result<RgbaImage> {
    let opt = Options::default();
    let tree = Tree::from_str(svg, &opt).map_err(|e| EngineError::Render(e.to_string()))?;
    let mut pixmap =
        Pixmap::new(width, height).ok_or_else(|| EngineError::Render("pixmap alloc".into()))?;
    // White base so uncovered pixels compare against a neutral background.
    pixmap.fill(resvg::tiny_skia::Color::WHITE);
    resvg::render(&tree, Transform::identity(), &mut pixmap.as_mut());
    Ok(RgbaImage {
        width,
        height,
        data: pixmap.data().to_vec(),
    })
}

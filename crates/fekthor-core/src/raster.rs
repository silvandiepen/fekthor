//! Engine-neutral raster image loading and buffers.

use crate::{EngineError, Result};
use image::GenericImageView;

/// A straight-alpha RGBA8 image buffer in row-major order.
#[derive(Clone)]
pub struct RgbaImage {
    pub width: u32,
    pub height: u32,
    /// `width * height * 4` bytes, R,G,B,A per pixel.
    pub data: Vec<u8>,
}

impl RgbaImage {
    pub fn from_path(path: &str) -> Result<Self> {
        let img = image::open(path).map_err(|e| EngineError::Decode(e.to_string()))?;
        let (width, height) = img.dimensions();
        let data = img.to_rgba8().into_raw();
        Ok(RgbaImage {
            width,
            height,
            data,
        })
    }

    #[inline]
    pub fn pixel(&self, x: u32, y: u32) -> [u8; 4] {
        let i = ((y * self.width + x) * 4) as usize;
        [
            self.data[i],
            self.data[i + 1],
            self.data[i + 2],
            self.data[i + 3],
        ]
    }

    pub fn save_png(&self, path: &str) -> Result<()> {
        let buf = image::RgbaImage::from_raw(self.width, self.height, self.data.clone())
            .ok_or_else(|| EngineError::Io("buffer size mismatch".into()))?;
        buf.save(path).map_err(|e| EngineError::Io(e.to_string()))
    }
}

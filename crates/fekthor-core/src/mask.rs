//! Binary foreground mask extraction.

use crate::raster::RgbaImage;

/// A binary foreground mask (`true` = ink/foreground).
pub struct Mask {
    pub width: u32,
    pub height: u32,
    pub fg: Vec<bool>,
}

#[inline]
fn luminance(p: [u8; 4]) -> f32 {
    0.299 * p[0] as f32 + 0.587 * p[1] as f32 + 0.114 * p[2] as f32
}

impl Mask {
    #[inline]
    pub fn at(&self, x: i64, y: i64) -> bool {
        if x < 0 || y < 0 || x >= self.width as i64 || y >= self.height as i64 {
            return false;
        }
        self.fg[(y as u32 * self.width + x as u32) as usize]
    }

    pub fn count(&self) -> usize {
        self.fg.iter().filter(|&&b| b).count()
    }
}

/// Foreground = dark pixels (ink on light paper) below `threshold` luminance.
pub fn foreground_dark(img: &RgbaImage, threshold: u8) -> Mask {
    let n = (img.width * img.height) as usize;
    let mut fg = vec![false; n];
    for (i, slot) in fg.iter_mut().enumerate() {
        let o = i * 4;
        let p = [
            img.data[o],
            img.data[o + 1],
            img.data[o + 2],
            img.data[o + 3],
        ];
        // Transparent pixels are background.
        *slot = p[3] >= 128 && luminance(p) < threshold as f32;
    }
    Mask {
        width: img.width,
        height: img.height,
        fg,
    }
}

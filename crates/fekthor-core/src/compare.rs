//! Render-back comparison metrics.
//!
//! Compares a rendered vector against the (cleaned) source raster. Reports both
//! pixel fidelity and an exact-match rate so overly complex or wrong results are
//! visible, not just average similarity (docs/TESTING.md, D-009).

use crate::raster::RgbaImage;
use serde::Serialize;

#[derive(Serialize, Clone, Copy)]
pub struct Metrics {
    /// Mean absolute per-channel difference over RGB (0 = identical).
    pub mean_abs: f64,
    /// Fraction of pixels whose max RGB channel diff is within tolerance.
    pub exact_pct: f64,
    /// Peak signal-to-noise ratio in dB (higher is better; `inf` if identical).
    pub psnr: f64,
    /// Tolerance used for `exact_pct`.
    pub tolerance: u8,
}

/// Compare two equally sized RGBA buffers over their RGB channels.
pub fn compare(source: &RgbaImage, rendered: &RgbaImage, tolerance: u8) -> Metrics {
    assert_eq!(source.width, rendered.width);
    assert_eq!(source.height, rendered.height);
    let n = (source.width * source.height) as usize;
    let mut sum_abs: u64 = 0;
    let mut sum_sq: u64 = 0;
    let mut exact: u64 = 0;
    for i in 0..n {
        let o = i * 4;
        let mut maxd = 0u8;
        for c in 0..3 {
            let a = source.data[o + c] as i32;
            let b = rendered.data[o + c] as i32;
            let d = (a - b).unsigned_abs() as u64;
            sum_abs += d;
            sum_sq += d * d;
            if d as u8 > maxd {
                maxd = d as u8;
            }
        }
        if maxd <= tolerance {
            exact += 1;
        }
    }
    let count = (n * 3) as f64;
    let mean_abs = sum_abs as f64 / count;
    let mse = sum_sq as f64 / count;
    let psnr = if mse <= f64::EPSILON {
        f64::INFINITY
    } else {
        20.0 * (255.0_f64).log10() - 10.0 * mse.log10()
    };
    Metrics {
        mean_abs,
        exact_pct: 100.0 * exact as f64 / n as f64,
        psnr,
        tolerance,
    }
}

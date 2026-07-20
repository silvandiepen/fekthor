//! Deterministic colour quantization.
//!
//! A coarse-histogram seeded k-means (Lloyd) over RGB. Seeding is deterministic
//! (top coarse buckets with spatial spread), so identical input and `k` produce
//! identical palettes and index maps.

use crate::raster::RgbaImage;

pub type Rgb = [u8; 3];

pub struct Quantized {
    pub width: u32,
    pub height: u32,
    pub palette: Vec<Rgb>,
    /// One palette index per pixel, row-major.
    pub indices: Vec<u16>,
}

#[inline]
fn dist2(a: Rgb, b: Rgb) -> i64 {
    let dr = a[0] as i64 - b[0] as i64;
    let dg = a[1] as i64 - b[1] as i64;
    let db = a[2] as i64 - b[2] as i64;
    dr * dr + dg * dg + db * db
}

/// Quantize to at most `k` colours with `iters` Lloyd iterations.
pub fn quantize(img: &RgbaImage, k: usize, iters: usize) -> Quantized {
    let n = (img.width * img.height) as usize;
    let px = |i: usize| -> Rgb {
        let o = i * 4;
        [img.data[o], img.data[o + 1], img.data[o + 2]]
    };

    // Coarse 4-bit-per-channel histogram for deterministic seeding.
    let mut hist = std::collections::HashMap::<u16, (u64, [u64; 3])>::new();
    for i in 0..n {
        let c = px(i);
        let key = ((c[0] as u16 >> 4) << 8) | ((c[1] as u16 >> 4) << 4) | (c[2] as u16 >> 4);
        let e = hist.entry(key).or_insert((0, [0; 3]));
        e.0 += 1;
        e.1[0] += c[0] as u64;
        e.1[1] += c[1] as u64;
        e.1[2] += c[2] as u64;
    }
    // Bucket mean colours sorted by frequency (ties broken by colour for determinism).
    let mut buckets: Vec<(u64, Rgb)> = hist
        .values()
        .map(|(count, sum)| {
            let mean = [
                (sum[0] / count) as u8,
                (sum[1] / count) as u8,
                (sum[2] / count) as u8,
            ];
            (*count, mean)
        })
        .collect();
    buckets.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));

    // Greedy spread seeding: take frequent buckets that are far from existing seeds.
    let min_sep2: i64 = 24 * 24;
    let mut seeds: Vec<Rgb> = Vec::new();
    for &(_, c) in &buckets {
        if seeds.len() >= k {
            break;
        }
        if seeds.iter().all(|&s| dist2(s, c) >= min_sep2) {
            seeds.push(c);
        }
    }
    // Fill remaining slots from the most frequent buckets if spread ran out.
    for &(_, c) in &buckets {
        if seeds.len() >= k {
            break;
        }
        if !seeds.contains(&c) {
            seeds.push(c);
        }
    }
    if seeds.is_empty() {
        seeds.push([0, 0, 0]);
    }

    // Lloyd iterations over a strided sample for speed, then a final full pass.
    let stride = (n / 200_000).max(1);
    let mut centroids = seeds.clone();
    for _ in 0..iters {
        let mut sums = vec![[0i64; 3]; centroids.len()];
        let mut counts = vec![0i64; centroids.len()];
        let mut i = 0;
        while i < n {
            let c = px(i);
            let mut best = 0usize;
            let mut bestd = i64::MAX;
            for (j, &cen) in centroids.iter().enumerate() {
                let d = dist2(c, cen);
                if d < bestd {
                    bestd = d;
                    best = j;
                }
            }
            sums[best][0] += c[0] as i64;
            sums[best][1] += c[1] as i64;
            sums[best][2] += c[2] as i64;
            counts[best] += 1;
            i += stride;
        }
        for j in 0..centroids.len() {
            if counts[j] > 0 {
                centroids[j] = [
                    (sums[j][0] / counts[j]) as u8,
                    (sums[j][1] / counts[j]) as u8,
                    (sums[j][2] / counts[j]) as u8,
                ];
            }
        }
    }

    // Final full assignment.
    let mut indices = vec![0u16; n];
    for (i, slot) in indices.iter_mut().enumerate() {
        let c = px(i);
        let mut best = 0usize;
        let mut bestd = i64::MAX;
        for (j, &cen) in centroids.iter().enumerate() {
            let d = dist2(c, cen);
            if d < bestd {
                bestd = d;
                best = j;
            }
        }
        *slot = best as u16;
    }

    Quantized {
        width: img.width,
        height: img.height,
        palette: centroids,
        indices,
    }
}

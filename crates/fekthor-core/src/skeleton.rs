//! Zhang-Suen thinning: reduce a foreground mask to a 1px-wide skeleton.
//!
//! Topology-preserving iterative thinning. Deterministic: the same mask always
//! yields the same skeleton. A medial-axis alternative can be added behind the
//! same interface later (docs O-002).

use crate::mask::Mask;

/// Thin a binary mask to its 1px skeleton.
pub fn thin(mask: &Mask) -> Mask {
    let w = mask.width as i64;
    let h = mask.height as i64;
    let mut g: Vec<u8> = mask.fg.iter().map(|&b| b as u8).collect();
    let idx = |x: i64, y: i64| (y * w + x) as usize;
    let get = |g: &[u8], x: i64, y: i64| -> u8 {
        if x < 0 || y < 0 || x >= w || y >= h {
            0
        } else {
            g[idx(x, y)]
        }
    };

    loop {
        let mut changed = false;
        for step in 0..2 {
            let mut to_del: Vec<usize> = Vec::new();
            for y in 0..h {
                for x in 0..w {
                    if g[idx(x, y)] == 0 {
                        continue;
                    }
                    // p2..p9 clockwise from north.
                    let p2 = get(&g, x, y - 1);
                    let p3 = get(&g, x + 1, y - 1);
                    let p4 = get(&g, x + 1, y);
                    let p5 = get(&g, x + 1, y + 1);
                    let p6 = get(&g, x, y + 1);
                    let p7 = get(&g, x - 1, y + 1);
                    let p8 = get(&g, x - 1, y);
                    let p9 = get(&g, x - 1, y - 1);
                    let neigh = [p2, p3, p4, p5, p6, p7, p8, p9];
                    let b: u8 = neigh.iter().sum();
                    if !(2..=6).contains(&b) {
                        continue;
                    }
                    // A = number of 0->1 transitions in the ordered sequence.
                    let mut a = 0;
                    for k in 0..8 {
                        if neigh[k] == 0 && neigh[(k + 1) % 8] == 1 {
                            a += 1;
                        }
                    }
                    if a != 1 {
                        continue;
                    }
                    let (c1, c2) = if step == 0 {
                        (p2 * p4 * p6, p4 * p6 * p8)
                    } else {
                        (p2 * p4 * p8, p2 * p6 * p8)
                    };
                    if c1 == 0 && c2 == 0 {
                        to_del.push(idx(x, y));
                    }
                }
            }
            if !to_del.is_empty() {
                changed = true;
                for i in to_del {
                    g[i] = 0;
                }
            }
        }
        if !changed {
            break;
        }
    }

    Mask {
        width: mask.width,
        height: mask.height,
        fg: g.iter().map(|&v| v == 1).collect(),
    }
}

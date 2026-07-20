//! Basic geometry: points, polygon area, and Douglas-Peucker simplification.

pub type Point = [f64; 2];

/// Signed area of a closed polygon (shoelace). Positive for counter-clockwise.
pub fn signed_area(poly: &[Point]) -> f64 {
    let n = poly.len();
    if n < 3 {
        return 0.0;
    }
    let mut a = 0.0;
    for i in 0..n {
        let p = poly[i];
        let q = poly[(i + 1) % n];
        a += p[0] * q[1] - q[0] * p[1];
    }
    a / 2.0
}

pub fn area(poly: &[Point]) -> f64 {
    signed_area(poly).abs()
}

/// Perpendicular distance from `p` to the line through `a`-`b`.
fn perp_dist(p: Point, a: Point, b: Point) -> f64 {
    let dx = b[0] - a[0];
    let dy = b[1] - a[1];
    let len = (dx * dx + dy * dy).sqrt();
    if len < 1e-9 {
        let ex = p[0] - a[0];
        let ey = p[1] - a[1];
        return (ex * ex + ey * ey).sqrt();
    }
    ((p[0] - a[0]) * dy - (p[1] - a[1]) * dx).abs() / len
}

/// Douglas-Peucker simplification of an open polyline.
pub fn simplify_open(pts: &[Point], epsilon: f64) -> Vec<Point> {
    if pts.len() < 3 {
        return pts.to_vec();
    }
    let mut dmax = 0.0;
    let mut index = 0;
    let end = pts.len() - 1;
    for (i, &p) in pts.iter().enumerate().take(end).skip(1) {
        let d = perp_dist(p, pts[0], pts[end]);
        if d > dmax {
            index = i;
            dmax = d;
        }
    }
    if dmax > epsilon {
        let mut left = simplify_open(&pts[..=index], epsilon);
        let right = simplify_open(&pts[index..], epsilon);
        left.pop();
        left.extend(right);
        left
    } else {
        vec![pts[0], pts[end]]
    }
}

/// Simplify a closed polygon while preserving closure. The polygon is treated as
/// a ring; the vertex furthest from the centroid anchors the split so the result
/// is stable under rotation of the input ordering.
pub fn simplify_closed(ring: &[Point], epsilon: f64) -> Vec<Point> {
    let n = ring.len();
    if n < 4 {
        return ring.to_vec();
    }
    // Anchor at the point furthest from the first vertex, split the ring there,
    // and simplify the resulting open chain (start == end anchor).
    let a = ring[0];
    let mut far = 0;
    let mut fardist = 0.0;
    for (i, &p) in ring.iter().enumerate() {
        let d = (p[0] - a[0]).powi(2) + (p[1] - a[1]).powi(2);
        if d > fardist {
            fardist = d;
            far = i;
        }
    }
    let mut chain: Vec<Point> = Vec::with_capacity(n + 1);
    for i in 0..=n {
        chain.push(ring[(far + i) % n]);
    }
    let mut simplified = simplify_open(&chain, epsilon);
    // Drop the duplicated closing vertex; the path serializer closes with `Z`.
    if simplified.len() > 1 {
        simplified.pop();
    }
    simplified
}

//! SVG export.
//!
//! Emits semantic SVG: filled paths keep `fill`/`fill-rule`; stroked paths keep
//! real `stroke` attributes (never expanded to outlines). Coordinates are
//! quantized to a fixed precision only at export.

use crate::document::{Element, VectorDocument};
use crate::geom::Point;

fn fmt_num(v: f64) -> String {
    // Fixed precision, trimmed. Quantize only at export (docs/DOCUMENT-MODEL.md).
    let s = format!("{:.2}", v);
    let s = s.trim_end_matches('0').trim_end_matches('.');
    if s.is_empty() || s == "-0" {
        "0".to_string()
    } else {
        s.to_string()
    }
}

fn hex(c: [u8; 3]) -> String {
    format!("#{:02x}{:02x}{:02x}", c[0], c[1], c[2])
}

fn ring_to_path(ring: &[Point]) -> String {
    let mut d = String::new();
    for (i, p) in ring.iter().enumerate() {
        if i == 0 {
            d.push('M');
        } else {
            d.push('L');
        }
        d.push_str(&fmt_num(p[0]));
        d.push(' ');
        d.push_str(&fmt_num(p[1]));
        d.push(' ');
    }
    d.push('Z');
    d
}

/// Serialize a document to a standards-based SVG string.
pub fn to_svg(doc: &VectorDocument) -> String {
    let mut s = String::new();
    s.push_str(&format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{w}\" height=\"{h}\" viewBox=\"0 0 {w} {h}\">\n",
        w = doc.width,
        h = doc.height
    ));
    for el in &doc.elements {
        match el {
            Element::Fill(f) => {
                let mut d = String::new();
                for ring in &f.rings {
                    if ring.len() >= 3 {
                        d.push_str(&ring_to_path(ring));
                    }
                }
                s.push_str(&format!(
                    "  <path id=\"{id}\" d=\"{d}\" fill=\"{c}\" fill-rule=\"evenodd\"/>\n",
                    id = f.id,
                    d = d,
                    c = hex(f.color)
                ));
            }
            Element::Stroke(st) => {
                let mut d = String::new();
                for (i, p) in st.points.iter().enumerate() {
                    d.push(if i == 0 { 'M' } else { 'L' });
                    d.push_str(&fmt_num(p[0]));
                    d.push(' ');
                    d.push_str(&fmt_num(p[1]));
                    d.push(' ');
                }
                if st.closed {
                    d.push('Z');
                }
                s.push_str(&format!(
                    "  <path id=\"{id}\" d=\"{d}\" fill=\"none\" stroke=\"{c}\" stroke-width=\"{w}\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n",
                    id = st.id,
                    d = d,
                    c = hex(st.color),
                    w = fmt_num(st.width)
                ));
            }
        }
    }
    s.push_str("</svg>\n");
    s
}

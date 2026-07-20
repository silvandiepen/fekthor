//! Fekthor CLI: convert a raster image to vector and report render-back metrics.
//!
//! Usage:
//!   fekthor process <input> [--mode shapes] [--colors N] [--epsilon E]
//!                            [--min-area A] [--out DIR]

use anyhow::{bail, Context, Result};
use fekthor_core::compare::compare;
use fekthor_core::document::VectorDocument;
use fekthor_core::raster::RgbaImage;
use fekthor_core::render::render_svg;
use fekthor_core::shapes::{self, ShapesConfig};
use fekthor_core::svg::to_svg;
use fekthor_core::Mode;
use std::fs;
use std::path::Path;

struct Args {
    input: String,
    mode: Mode,
    colors: usize,
    epsilon: f64,
    min_area: f64,
    out: String,
}

fn parse_args() -> Result<Args> {
    let mut a: Vec<String> = std::env::args().skip(1).collect();
    if a.first().map(|s| s.as_str()) != Some("process") {
        bail!("usage: fekthor process <input> [--mode shapes] [--colors N] [--epsilon E] [--min-area A] [--out DIR]");
    }
    a.remove(0);
    if a.is_empty() {
        bail!("missing <input>");
    }
    let input = a.remove(0);
    let mut mode = Mode::Shapes;
    let mut colors = 16usize;
    let mut epsilon = 1.0f64;
    let mut min_area = 6.0f64;
    let mut out = "out".to_string();
    let mut i = 0;
    while i < a.len() {
        match a[i].as_str() {
            "--mode" => {
                i += 1;
                mode = match a.get(i).map(|s| s.as_str()) {
                    Some("shapes") => Mode::Shapes,
                    Some("strokes") => Mode::Strokes,
                    Some("gradient") => Mode::Gradient,
                    other => bail!("unknown mode: {:?}", other),
                };
            }
            "--colors" => {
                i += 1;
                colors = a.get(i).context("--colors needs a value")?.parse()?;
            }
            "--epsilon" => {
                i += 1;
                epsilon = a.get(i).context("--epsilon needs a value")?.parse()?;
            }
            "--min-area" => {
                i += 1;
                min_area = a.get(i).context("--min-area needs a value")?.parse()?;
            }
            "--out" => {
                i += 1;
                out = a.get(i).context("--out needs a value")?.clone();
            }
            other => bail!("unknown argument: {other}"),
        }
        i += 1;
    }
    Ok(Args {
        input,
        mode,
        colors,
        epsilon,
        min_area,
        out,
    })
}

fn main() -> Result<()> {
    let args = parse_args()?;
    let img = RgbaImage::from_path(&args.input)
        .map_err(|e| anyhow::anyhow!("load {}: {e}", args.input))?;

    let doc: VectorDocument = match args.mode {
        Mode::Shapes => shapes::run(
            &img,
            &ShapesConfig {
                colors: args.colors,
                iters: 8,
                epsilon: args.epsilon,
                min_area: args.min_area,
            },
        ),
        Mode::Strokes | Mode::Gradient => {
            bail!("mode not implemented yet: {:?}", args.mode)
        }
    };

    let svg = to_svg(&doc);
    let rendered =
        render_svg(&svg, img.width, img.height).map_err(|e| anyhow::anyhow!("render-back: {e}"))?;
    let metrics = compare(&img, &rendered, 8);

    fs::create_dir_all(&args.out)?;
    let out = Path::new(&args.out);
    fs::write(out.join("vector.svg"), &svg)?;
    rendered
        .save_png(out.join("render.png").to_str().unwrap())
        .map_err(|e| anyhow::anyhow!("save render: {e}"))?;

    let report = serde_json::json!({
        "input": args.input,
        "mode": args.mode,
        "width": img.width,
        "height": img.height,
        "fills": doc.fill_count(),
        "strokes": doc.stroke_count(),
        "nodes": doc.node_count(),
        "svg_bytes": svg.len(),
        "metrics": metrics,
    });
    fs::write(
        out.join("metrics.json"),
        serde_json::to_string_pretty(&report)?,
    )?;

    println!(
        "mode={:?} fills={} nodes={} svg={}KB | exact={:.2}% mean_abs={:.2} psnr={:.2}dB",
        args.mode,
        doc.fill_count(),
        doc.node_count(),
        svg.len() / 1024,
        metrics.exact_pct,
        metrics.mean_abs,
        metrics.psnr,
    );
    Ok(())
}

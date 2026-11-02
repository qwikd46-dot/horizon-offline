//! Horizon Extras' water interactions (docs/extras.md): a player or mob moving in water pushes a
//! ripple into the surface, and a dropped item makes a small one. Not in vanilla; off by default.
//!
//! Client-only and at render time: the fluid engine, chunk meshes and saves never see it. Each frame
//! the game picks the [`MAX`] sources nearest the camera and the shader pack reads them from `Frame`;
//! the pack's water stage turns each into a decaying ring on the surface. Off, the list is empty and
//! the pack skips the loop. There is no simulation texture: the pack cannot run one (its stages are
//! sky, material and post), so a source is an analytic ripple, not a step of a height field.
use glam::DVec3;

/// Sources the shader reads: `Frame.water_disturb` in inputs.rs and the pack's water stage.
pub const MAX: usize = 16;
/// Sources farther than this from the camera disturb nothing it can see.
const REACH: f64 = 96.0;

/// One disturbance this frame: where the surface is (world space, at the water's top face), how wide
/// the ring is in blocks, and how strong it is (1 is a full push, less is a lighter touch).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Source {
    pub at: DVec3,
    pub radius: f32,
    pub strength: f32,
}

/// The [`MAX`] sources nearest `camera` within reach, as the shader reads them: camera-relative
/// position in the xz plane, ring radius and strength. Overwrites `out`.
pub fn select(sources: &[Source], camera: DVec3, out: &mut Vec<[f32; 4]>) {
    out.clear();
    let key = |s: &Source| s.at.distance_squared(camera);
    let mut near: Vec<&Source> = sources
        .iter()
        .filter(|s| s.strength > 0.0 && key(s) <= REACH * REACH)
        .collect();
    near.sort_by(|a, b| key(a).total_cmp(&key(b)));
    out.extend(near.into_iter().take(MAX).map(|s| {
        let p = (s.at - camera).as_vec3();
        [p.x, p.z, s.radius.max(0.1), s.strength.clamp(0.0, 1.0)]
    }));
}

/// The ripple a source adds to the surface height at `pos` (camera-relative), for tests: a ring that
/// is zero at the centre and at the edge, strongest in between. The WGSL in the pack's water stage is
/// the same shape.
pub fn ripple_at(pos: [f32; 2], sources: &[[f32; 4]]) -> f32 {
    let mut sum = 0.0f32;
    for s in sources {
        let dx = pos[0] - s[0];
        let dz = pos[1] - s[1];
        let r = (dx * dx + dz * dz).sqrt();
        if r >= s[2] {
            continue;
        }
        let x = r / s[2];
        // A ring: sin(pi*x) is 0 at the centre and the rim, 1 in the middle.
        sum += (x * std::f32::consts::PI).sin() * s[3];
    }
    sum
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nearest_sources_win() {
        let camera = DVec3::new(100.0, 64.0, 100.0);
        let mut sources: Vec<Source> = (0..40)
            .map(|i| Source {
                at: camera + DVec3::new(f64::from(i), 0.0, 0.0),
                radius: 3.0,
                strength: 1.0,
            })
            .collect();
        sources.push(Source {
            at: camera + DVec3::new(0.5, 0.0, 0.0),
            radius: 3.0,
            strength: 0.0,
        });
        sources.push(Source {
            at: camera + DVec3::new(0.0, 0.0, 200.0),
            radius: 3.0,
            strength: 1.0,
        });
        let mut out = Vec::new();
        select(&sources, camera, &mut out);
        assert_eq!(out.len(), MAX);
        assert_eq!(out[0], [0.0, 0.0, 3.0, 1.0]);
        assert_eq!(out[MAX - 1][0], (MAX - 1) as f32);
        select(&[], camera, &mut out);
        assert!(out.is_empty());
    }

    #[test]
    fn a_ripple_is_a_ring() {
        let sources = [[0.0, 0.0, 4.0, 1.0]];
        // Zero at the centre and at the rim, positive in between.
        assert!(ripple_at([0.0, 0.0], &sources).abs() < 1e-5);
        assert!(ripple_at([4.0, 0.0], &sources).abs() < 1e-5);
        assert!(ripple_at([2.0, 0.0], &sources) > 0.9);
        // Nothing outside the ring.
        assert_eq!(ripple_at([9.0, 0.0], &sources), 0.0);
    }
}

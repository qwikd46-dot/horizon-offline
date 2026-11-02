//! Horizon Extras' water interactions (`horizon_client::water`): the ripples near the camera this
//! frame. Nothing is gathered while the extra is off.
use super::Game;
use glam::DVec3;
use horizon_client::blocks::Fluid;
use horizon_client::water::{self, Source};
use horizon_core::geometry::Vec3;

impl Game<'_> {
    /// Fills `water_sources` for the frame: the local player, the mobs and the dropped items in
    /// water, the nearest [`water::MAX`] of them. Each source sits on the water's top face so the
    /// pack draws its ring on the surface, not on the entity.
    pub(super) fn gather_water_ripples(&mut self, camera: DVec3, alpha: f64) {
        let mut out = std::mem::take(&mut self.water_sources);
        out.clear();
        if !self.settings.extras.water_ripples {
            self.water_sources = out;
            return;
        }
        let mut sources = Vec::new();
        // The local player: a wake whose strength grows with their speed through the water.
        if let Some(p) = &self.player
            && !p.spectator
        {
            let feet: Vec3 = self
                .previous_position
                .lerp(p.position, self.clock.camera_fraction());
            if let Some(y) = self.water_surface_at(feet) {
                let speed = (p.velocity.x * p.velocity.x + p.velocity.z * p.velocity.z).sqrt();
                sources.push(Source {
                    at: DVec3::new(feet.x, y, feet.z),
                    radius: 3.0,
                    strength: wake(speed),
                });
            }
        }
        for m in self.mobs.iter().filter(|m| !m.removed && m.fluids.in_water) {
            let at: Vec3 = m.previous.lerp(m.position, alpha);
            if let Some(y) = self.water_surface_at(at) {
                let speed = (m.velocity.x * m.velocity.x + m.velocity.z * m.velocity.z).sqrt();
                sources.push(Source {
                    at: DVec3::new(at.x, y, at.z),
                    radius: 2.0,
                    strength: wake(speed),
                });
            }
        }
        for item in &self.dropped {
            let at: Vec3 = item.previous.lerp(item.position, alpha);
            if let Some(y) = self.water_surface_at(at) {
                sources.push(Source {
                    at: DVec3::new(at.x, y, at.z),
                    radius: 1.6,
                    strength: 0.5,
                });
            }
        }
        water::select(&sources, camera, &mut out);
        self.water_sources = out;
    }

    /// The water's top face just above `at`, when the entity at `at` stands in water: the first
    /// non-water above the highest water block in the column under its feet, within 3 blocks.
    fn water_surface_at(&self, at: Vec3) -> Option<f64> {
        let x = at.x.floor() as i32;
        let z = at.z.floor() as i32;
        let feet = at.y.floor() as i32;
        let is_water =
            |y: i32| self.res.facts().get(self.world.block(x, y, z)).fluid == Fluid::Water;
        if !is_water(feet) && !is_water(feet - 1) {
            return None;
        }
        let mut top = feet;
        while top + 1 < feet + 4 && is_water(top + 1) {
            top += 1;
        }
        Some(f64::from(top) + 1.0)
    }
}

/// The strength of a wake at `speed` blocks per tick: a still entity barely disturbs the surface,
/// a swimmer pushes a full ring.
fn wake(speed: f64) -> f32 {
    (0.25 + speed as f32 * 0.5).min(1.0)
}

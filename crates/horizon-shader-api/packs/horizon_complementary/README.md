# Horizon Complementary

The shader pack Horizon ships with: a complementary/BSL-inspired look built only from Horizon's
shader API (WGSL, no other mod's code), with a sky stage, a material stage and three post passes.
The launcher writes it into the game's `shaderpacks/` before Play, and the game writes it on its
first run, so it is on Options > Horizon Settings > Shader Packs without downloading anything. The
launcher also brings an older copy up to date in place, so a pack you never edited updates itself.

2.0.0 ports Complementary Reimagined (r5.9.3): its noon, sunset and night skies, its sun, moon and ambient light colours, and its Lottes tonemap, applied once in linear light. 2.1.0 replaces the water surface with a port of **Glistening Water V1.1**: a physically-timed Gerstner wave field with its own sun glitter. Every light, tint and quality value is a WGSL `override`
set on the pack's settings screen, so the look is tuned live and a branch on an option is on a
constant the GPU skips.

- **Atmosphere** (`sky.wgsl`): Complementary's up / middle / down sky gradient for noon, sunset and
  night, driven by the sun's height and the rain, tonemapped once. On top of it a bright sun with a
  hot core and a wide soft halo, a horizon that reddens on the sun's side as it sets, a moon with a
  soft blue glow
  and a faint band of light around its side of the sky at night, a drifting cloud deck lit by the
  moon (silver edges, warm undersides at dusk) that thickens and speeds up in rain, and only a
  little haze low in the sky. A one-bit dither removes gradient banding.
- **Material** (`material.wgsl`): Complementary's light — its sun (by day) or moon (by night)
  as a direct light on what the sky reaches, its noon / sunset / night ambient colours, warm block
  light and a floor so caves are never black — computed in linear light and tonemapped once. Water is
  shaded as **crystal-clear water**: vanilla's streaky water texture is dropped and the surface reads
  as a clean pane tinted only by the little light the water absorbs on the way through, over
  **Glistening Water V1.1**: a **nine-wave Gerstner field**
  (six lake-scale swells and three capillary ripples) whose components each travel at the real
  deep-water speed (`sqrt(g * k)`), so the crests move at the right rate and drift past each other
  instead of locking into a repeating grid. The field is anchored to the world, so it stays put as you
  walk, and it only tilts the **surface normal** (the geometry is vanilla's water block). On top of it a
  **dielectric Fresnel** (about 2% facing the surface, near total at a grazing angle) with a sky
  reflection, the **glisten** — the wave normal throwing the sun back at the eye as a glittering road
  along the sun's path — a **GGX** moon glint, a clear-water absorption that turns the surface teal with
  **Water clarity**, and **caustics**, the sun's bright web shimmering on the water by day. **Rain**
  pricks the surface with a grid of expanding rings, and a **swimmer** leaves rings around the camera,
  both procedural so the pack needs nothing but the frame every build of the game gives it. The waves,
  the rings, the reflection and the glint all fade out with distance, so far water is a calm flat sheet.
  Only a little aerial haze, and only in the last stretch before the far plane.
- **Shadows** (`post/shadows.wgsl`): screen-space ambient occlusion and contact shadows from the
  depth already in the picture (the engine has none of its own): the dark seam where surfaces meet
  and the soft shade under objects. The taps are taken at a small, **clamped screen radius** with a
  depth bias and a gentle strength, so the pattern stays pinned to the geometry instead of swimming
  across a flat face, and the far half of the view is skipped before any tap.
- **Bloom** (`post/bloom.wgsl`): golden-angle spiral taps whose offsets scale with the picture's
  height, so the bloom looks the same at any resolution; a soft knee so the threshold never
  flickers. It is the heaviest pass, so its tap count follows the quality preset.
- **Tonemap and grade** (`common.wgsl` + `post/grade.wgsl`): Complementary's Lottes curve runs once
  in linear light in the sky and material stages, so nothing is curved twice; the grade adds
  exposure, a gentle S-curve, golden light at sunrise and sunset, a **slow night exposure** and a
  blue-tinted shadow lift so the dark stays readable without crushing to black, human
  **night-vision desaturation** (dark regions cool and desaturate, greens stay readable), mid-tone
  contrast, saturation and a vignette.

Thirty-plus options on Options > Horizon Settings > Shader Packs. Start with **Night quality**
(Low/Medium/High/Ultra), which caps the Shadows, Bloom and Cloud quality taps at once; the individual
settings can go lower, never higher. **Performance mode** is the lowest quality everywhere at once,
for a weak GPU. A commented reference for every option is in
`crates/horizon-shader-api/packs/horizon_complementary-settings.example.toml`.

What the pack cannot do, because the API has no such stage: a real shadow map, screen-space
reflections, half-resolution post passes, a light list, or a surface normal on the material stage.
Those are engine work and are written up in `docs/shader-night-quality-engine.md`. In particular the
pack cannot cast **real sun or moon shadows**: `StageKind` is only `sky`, `material` and `post`, and
none of them sees a shadow map, so the "Shadows" pass here is screen-space occlusion from the depth
buffer, not a shadow map. A shadow stage is the single biggest graphics feature the engine still
needs.

Check it with:

```sh
cargo run -p horizon-shader-api --bin horizon-shader -- check \
  crates/horizon-shader-api/packs/horizon_complementary
```

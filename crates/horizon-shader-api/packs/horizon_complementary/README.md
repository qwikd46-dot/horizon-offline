# Horizon Complementary

The shader pack Horizon ships with: a complementary/BSL-inspired look built only from Horizon's
shader API (WGSL, no other mod's code), with a sky stage, a material stage and three post passes.
The launcher writes it into the game's `shaderpacks/` before Play, and the game writes it on its
first run, so it is on Options > Horizon Settings > Shader Packs without downloading anything. The
launcher also brings an older copy up to date in place, so a pack you never edited updates itself.

Dusk, dawn and night are the focus of 1.3.0. Every light, tint and quality value is a WGSL `override`
set on the pack's settings screen, so the look is tuned live and a branch on an option is on a
constant the GPU skips.

- **Atmosphere** (`sky.wgsl`): a bright sun with a hot core and a wide soft halo, a horizon that
  reddens on the sun's side as it sets, a deeper blue overhead by day, a moon with a soft blue glow
  and a faint band of light around its side of the sky at night, a drifting cloud deck lit by the
  moon (silver edges, warm undersides at dusk) that thickens and speeds up in rain, and only a
  little haze low in the sky. A one-bit dither removes gradient banding.
- **Material** (`material.wgsl`): vanilla's lightmap with torch light pulled toward amber, a cool
  **moonlight** that lights canopy, trunks and hills on a clear night, a blue night ambient with a
  ground bounce so shadows are deep blue, not black, a weak warm light from the low sun at dusk, and
  real travelling waves on water with a **moon glint**, a sky reflection that grows at grazing
  angles and a sun glint by day. Only a little aerial haze, and only near the far plane.
- **Shadows** (`post/shadows.wgsl`): screen-space ambient occlusion and contact shadows from the
  depth already in the picture (the engine has none of its own): the dark seam where surfaces meet
  and the soft shade under objects. A world-space radius shrinks with distance, so it does not
  shimmer; the far half of the view is skipped before any tap.
- **Bloom** (`post/bloom.wgsl`): golden-angle spiral taps whose offsets scale with the picture's
  height, so the bloom looks the same at any resolution; a soft knee so the threshold never
  flickers. It is the heaviest pass, so its tap count follows the quality preset.
- **Grade** (`post/grade.wgsl`): exposure, a filmic (ACES) curve or a gentler shoulder, golden light
  at sunrise and sunset, a **slow night exposure** and a blue-tinted shadow lift so the dark stays
  readable without crushing to black, human **night-vision desaturation** (dark regions cool and
  desaturate, greens stay readable), mid-tone contrast, saturation and a vignette.

Thirty options on Options > Horizon Settings > Shader Packs. Start with **Night quality**
(Low/Medium/High/Ultra), which caps the Shadows, Bloom and Cloud quality taps at once; the individual
settings can go lower, never higher. **Performance mode** is the lowest quality everywhere at once,
for a weak GPU. A commented reference for every option is in
`crates/horizon-shader-api/packs/horizon_complementary-settings.example.toml`.

What the pack cannot do, because the API has no such stage: a real shadow map, screen-space
reflections, half-resolution post passes, a light list, or a surface normal on the material stage.
Those are engine work and are written up in `docs/shader-night-quality-engine.md`.

Check it with:

```sh
cargo run -p horizon-shader-api --bin horizon-shader -- check \
  crates/horizon-shader-api/packs/horizon_complementary
```

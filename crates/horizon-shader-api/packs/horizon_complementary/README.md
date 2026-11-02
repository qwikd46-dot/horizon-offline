# Horizon Complementary

The shader pack Horizon ships with: a complementary/BSL-inspired look built only from Horizon's
shader API (WGSL, no other mod's code), with a sky stage, a material stage and three post passes.
The launcher writes it into the game's `shaderpacks/` before Play, and the game writes it on its
first run, so it is on Options > Horizon Settings > Shader Packs without downloading anything.

- **Atmosphere** (`sky.wgsl`): a bright sun with a hot core and a wide soft halo, a horizon that
  reddens on the sun's side as it sets, a deeper blue overhead by day, a faint moonlight glow at
  night, a drifting two-octave cloud deck that thickens and speeds up in rain, and only a little
  haze where the sky meets the ground. A one-bit dither removes gradient banding.
- **Material** (`material.wgsl`): vanilla's lightmap with torch light pulled toward amber, a cool
  lift in the open at night, real travelling waves on water with a moving sun highlight and a sky
  reflection that grows at grazing angles, and only a little aerial haze near the far plane.
- **Shadows** (`post/shadows.wgsl`): screen-space ambient occlusion and contact shadows from the
  depth already in the picture (the engine has none of its own): the dark seam where surfaces meet
  and the soft shade under objects. A world-space radius shrinks with distance, so it does not
  shimmer.
- **Bloom** (`post/bloom.wgsl`): golden-angle spiral taps (10 tight, 14 wide) whose offsets scale
  with the picture's height, so the bloom looks the same at any resolution; a soft knee so the
  threshold never flickers.
- **Grade** (`post/grade.wgsl`): exposure, a filmic (ACES) curve or a gentler shoulder, golden
  light at sunrise and sunset, slightly cooled shadows, mid-tone contrast, saturation and a
  vignette.

Twenty-two options on Options > Horizon Settings > Shader Packs, from `Sun glow`, `Water waves`,
`Water sun glint`, `Water reflection`, `Shadows` and `Fog amount` to the grade. `Performance mode`
halves the occlusion taps, drops the second cloud octave and the wide bloom ring.

Check it with:

```sh
cargo run -p horizon-shader-api --bin horizon-shader -- check \
  crates/horizon-shader-api/packs/horizon_complementary
```

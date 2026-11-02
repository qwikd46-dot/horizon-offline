# Horizon Complementary

The shader pack Horizon ships with: a complementary/BSL-inspired look built only from Horizon's
shader API (WGSL, no other mod's code), with a sky stage, a material stage and two post passes.
The launcher writes it into the game's `shaderpacks/` before Play, and the game writes it on its
first run, so it is on Options > Horizon Settings > Shader Packs without downloading anything.

- **Atmosphere** (`sky.wgsl`): forward scattering around the sun (a tight core and a wide wash,
  strongest at sunrise and sunset), a horizon that reddens on the sun's side, a deeper blue
  overhead by day, a faint moonlight glow at night, a drifting two-octave cloud deck that
  thickens and speeds up in rain, and haze that takes the sun's tint where the sky meets the
  ground. A one-bit dither removes gradient banding.
- **Material** (`material.wgsl`): vanilla's lightmap with torch light pulled toward amber, a cool
  lift in the open at night, a view-angle sun glint and a touch of sky colour on water and ice,
  and aerial haze toward vanilla's fog.
- **Bloom** (`post/bloom.wgsl`): golden-angle spiral taps (10 tight, 14 wide) whose offsets scale
  with the picture's height, so the bloom looks the same at any resolution; a soft knee so the
  threshold never flickers.
- **Grade** (`post/grade.wgsl`): exposure, a filmic (ACES) curve or a gentler shoulder, golden
  light at sunrise and sunset, slightly cooled shadows, mid-tone contrast, saturation and a
  vignette.

Twelve options on Options > Horizon Settings > Shader Packs; `Performance mode` drops the second
cloud octave and the wide bloom ring.

Check it with:

```sh
cargo run -p horizon-shader-api --bin horizon-shader -- check \
  crates/horizon-shader-api/packs/horizon_complementary
```

# Horizon Complementary

The shader pack Horizon ships with: a complementary/BSL-inspired look built only from Horizon's
shader API (WGSL, no other mod's code), with a sky stage, a material stage and two post passes.

- **Atmosphere** (`sky.wgsl`): a warm halo around a low sun, a deeper blue overhead by day, a faint
  moonlight glow at night, a drifting cloud layer and haze where the sky meets the ground.
- **Material** (`material.wgsl`): vanilla's lightmap with torch light pulled toward amber, a cool
  lift in the open at night, a sun glint on water and ice, and aerial haze toward vanilla's fog.
- **Bloom** (`post/bloom.wgsl`): two rings of taps (8 + 12) scaled with the picture's height, with
  the sky glowing a quarter as much by day.
- **Grade** (`post/grade.wgsl`): exposure, a filmic (ACES) curve or a gentler shoulder, golden light
  at sunrise and sunset, mid-tone contrast, saturation and a vignette.

Twelve options on Options > Horizon Settings > Shader Packs; `Performance mode` drops the second
cloud octave and the outer bloom ring.

Check it with:

```sh
cargo run -p horizon-shader-api --bin horizon-shader -- check \
  crates/horizon-shader-api/packs/horizon_complementary
```

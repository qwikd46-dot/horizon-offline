# Night quality: what the engine must do (handoff for the optimization mod / upstream)

The shader pack can only fill `[sky]`, `[material]` and up to 8 `[[post]]` passes at the world's
resolution (see `docs/shader-night-quality.md`). These items are beyond that API, so they belong in
the engine (this fork's game crates) or upstream `horizon-rust/horizon`. They are listed so nothing is
silently dropped, and so the optimization mod knows what to fix. No code here changes the mod.

Each item names the files it would touch and why.

## 1. Half-resolution bloom, AO and fog with a depth-aware upsample
`gfx/pack_post.rs` runs every pack post pass at the world's size. Give a pass a resolution scale in
the manifest (`[[post]] scale = 0.5`) and have the renderer allocate that target, then add a
depth-aware bilateral upsample before the next full-res pass. The pack's bloom and AO would then cost
a quarter of the pixels. Expected: ~0.6-1.0 ms at 1080p, the single biggest saving. Needs a history
buffer for temporal reuse (the engine already has `world_post.wgsl`'s TAA history to copy the pattern
from), with proper rejection to avoid ghosting.

## 2. Real cascaded moon shadows reusing the sun's shadow map
`gfx/pack_shadow.rs` already builds `shadowtex0/1` and `shadowcolor0/1` with a shadow camera, and
`gfx.rs` has `shadow_visible` / `shadow_runs` and `pack_uniforms.rs::shadow_light` (the sun by day,
the moon by night). A pack with a shadow stage gets all of it. To light night terrain without a
second map: at night point the same shadow camera along `moon_direction`, keep only the nearest two
cascades (or bands, `shadow_runs`), and stop drawing the far ones — they contribute nothing at night.
Then the material stage can sample `shadowtex0` for a soft moon shadow. Expected: soft long moon
shadows at no extra memory, and *faster* than day because fewer cascades draw.

## 3. Screen-space reflections for water, with a sky/moon fallback
A post pass cannot raymarch the world's colour usefully without the scene colour bound as both source
and target, and it has no sky texture. Add an engine SSR pass (half-res, a handful of steps, faded at
the screen edges) that the material stage can sample for water, with a sky-colour fallback including
the moon disc where SSR has no hit. This is what makes night water reflect the moon and stars.

## 4. Half-resolution clouds with temporal reuse
`clouds.rs` builds a mesh drawn at full res. Render the cloud layer into a half-res target with
temporal accumulation and a depth-aware upsample, and light it from the moon (silver-blue edges,
brighter rim toward the moon, darker bellies). Optional cloud shadows on the ground only if they fit
the budget.

## 5. Clustered / tiled light list, flicker, coloured bounce
`dynamic_light.rs` picks the 16 nearest sources; `terrain.wgsl::dynamic_block_light` loops them per
fragment. A tiled or clustered light list (per 16x16 tile, culled by distance, importance and
frustum, capped per tile) lets many torches not tank fps, and lets lights carry a colour and a flicker
phase for fire and torches, with a warm bounce onto nearby blocks.

## 6. Light the hand and entities with the material stage
`native_material.rs` wires the pack's `material` only into terrain. The hand (`gfx.rs`, depth cleared)
and entities (`entity.wgsl`) draw with vanilla's material, so a pack cannot light the held item. Give
them the pack's material stage, or at least the same moon/sky/torch lighting, so the held item is not
flat and unlit at night.

## 7. Moon phase in `Frame`; per-pass engine timings
`Frame` (`inputs.rs`) has `sun_direction` and `moon_direction` but not the moon phase; the pack
derives it from `game_time`. Add `moon_phase` (0-7) so phase-scaled moonlight is exact. Also extend
`gfx/pack_timing.rs` (or add engine timings) so the F3 overlay shows the engine's own passes (terrain,
sky, clouds, shadow, HDR), not only the pack's — the task's per-pass table needs them.

## 8. Log chunk-load hitches separately
The 335-570 ms spikes are chunk-load hitches from the optimization mod, not the shader. The engine's
frame timing should mark a frame as a load hitch (a chunk upload that frame) so the shader/GPU
measurements can exclude it, and `graphics_bench.py` should drop those frames from its percentiles.

# Night, dusk and dawn: measurement and plan

STEP 0 of the "make dusk/dawn/night excellent and faster" task. It records the pipeline map, the
measurement method, the frame budget, what the shader pack can and cannot reach, and the ranked fix
list. Everything stays in Rust/WGSL, as Horizon's shader API requires.

## 1. Pipeline map (pass order, targets, uniforms)

The renderer draws a frame in this order (`crates/horizon-client-render/src/gfx.rs`, `fn draw_frame`):

| # | Pass | Target | Notes |
|---|---|---|---|
| 1 | Sky dome | world colour + depth | `native_sky` (pack `sky` stage) or vanilla's sky; the sun, moon, stars and clouds are drawn **over** it |
| 2 | Terrain, solid + cutout | world colour | `terrain.wgsl` / the pack `material` stage |
| 3 | Entities, block entities, particles | world colour | `entity.wgsl`; not the pack's material |
| 4 | Shadow-map pass (only with a pack that has a shadow stage) | `shadowtex0/1`, `shadowcolor0/1` | `pack_shadow.rs`; **none of Horizon's own packs use it** |
| 5 | Translucent terrain (water, ice, stained glass) | world colour | the pack's material, `translucent` = true |
| 6 | Weather, clouds | world colour | clouds are a **prebuilt mesh** (`clouds.rs`), drawn, not ray-marched |
| 7 | Pack post passes (up to 8) | world-sized colour, ping-pong | `pack_post.rs`; each reads `scene_color`, `scene_depth`, `previous` |
| 8 | Hand and held item | world colour (depth cleared) | **not** the pack's material (no `material` for hand/entities) |
| 9 | `world_post` (FXAA or TAA) | screen | only with a non-vanilla setting |
| 10 | HDR output | swapchain | `hdr.wgsl` |

Targets: the world renders at the resolution scale into `Rgba16Float` (`native_post::INTERMEDIATE`);
depth is `Depth32Float`, **reversed** (1 near, 0 far/sky). Pack post passes run at the world's size.
The lightmap is a 16x16 `Rgba8` texture (sky level x block level), rebuilt when the game's light
changes; `terrain.wgsl::sample_lightmap(sky, block)` is the whole of vanilla's lighting.

Uniforms the pack sees: `Frame` (`inputs.rs`) — matrices, `camera_position`, `time`, `sun_direction`,
`moon_direction`, `day_time`, `game_time`, `sky_color`, `fog_color`, `rain`, `thunder`, `resolution`,
`eye_light`, `fog_start/end`, `render_distance`, `far`, `night_vision`, `darkness`, `brightness`,
`eye_in`, `dimension`. Time of day: `day_time` (0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight) and
`game_time`. Moon phase: **not** in `Frame`; the Iris-format loader reads `moonPhase` from
`worldTime`, and `pack_uniforms.rs` computes it as `(game_time / 24000) % 8`, so the phase is
derivable in the pack from `game_time`. Sun/moon direction come from `sky.sun_angle` / `sky.moon_angle`
(`SkyRenderer`), filled in `native_post::frame_inputs`.

## 2. How to measure (STEP 0.2)

The repo already has the per-pass instrumentation: `gfx/pack_timing.rs` records a GPU timestamp pair
per pack pass, one frame at a time, resolved later without stalling the CPU. It is shown in the F3
overlay ("shader pack" group, `debug_overlay::shader_pass_lines`) and logged every 30 timed frames
with `HORIZON_SHADER_PACK_TIMING=1` as `shader pack GPU time per pass (median ms ...)`. It only times
**pack** passes; the engine's terrain/sky/cloud/HDR cost is not in it.

To get a day-vs-night table, use `tools/graphics_bench.py`, which drives a seeded creative world over
fixed flights and reports avg FPS, 1% lows, percentiles, CPU ms and GPU ms (from timestamp queries),
at render distances 8/16/32, on the window (lavapipe here) or `--offscreen` for the discrete GPU. The
five comparison spots (sunset over the valley, full moon overhead, looking down at the lake, the lava
area, the forest canopy at night) and the time-of-day commands are the task's protocol; `graphics_bench`
covers valley/forest/ocean/mountain and can be extended with a night pass.

**Environment note (honest limit).** This sandbox has no GPU (`/dev/dri` absent; only lavapipe is
available, and only with the game's assets in `.local/`, which are not present — they are Mojang's
files and are never committed). So I could not run the game or capture real frame times here. The
per-pass table in the PR is therefore **analytical** (from the shader cost model: the `horizon-shader
check` expression and texture-read counts, which the game and CI use) and the numbers must be
confirmed on the test machine with the F3 overlay and `graphics_bench.py`. The instrumentation to do
it is already in the tree; nothing new is needed to measure.

## 3. Why night is slower (STEP 0.3, by analysis)

Night is not slower in the **engine** in any night-specific way: `terrain.wgsl` is the same shader
day and night, cloud geometry is the same mesh, stars are a fixed ~780-1500-triangle buffer, and the
shadow pass only exists for a pack that has a shadow stage (none of Horizon's own packs do). The
engine's per-frame cost is essentially time-of-day independent. The time-of-day dependence is the
**scene** (a dark sky with a camera looking down shows more terrain, water and translucency) plus the
pack's own cost, which is **constant** day and night:

1. **Bloom (`post/bloom.wgsl`)** is the heaviest pack pass: up to 24 `textureSampleLevel` taps of the
   full-resolution picture, every frame, whatever the brightness. The tap count never drops.
2. **The sky stage** runs two octaves of `noise2` (8 hash evaluations) per sky pixel for the cloud
   deck, plus the sun/moon/horizon math, unconditionally.
3. **Three full-resolution post passes** (`shadows`, `bloom`, `grade`) each read and write the whole
   world-sized target. At a high resolution scale this is the pack's dominant GPU time.
4. **`night_boost`** adds a per-fragment `mix`/add in the material stage, which runs on every terrain
   fragment, the most-filled pass.

A pack **cannot change a pass's resolution** (all post passes run at the world's size; the manifest
has no per-pass scale), so the pack's lever is **fewer texture reads and less per-pixel math**, not
half-resolution. Half-resolution bloom/AO/fog is engine work (see section 5). That is the honest
constraint, and it is why the pack fixes below cut taps and math rather than resolution.

## 4. Frame budget (target 60 fps = 16.6 ms)

Shadows 2.0 | Geometry+lighting 4.0 | Sky+stars+clouds 1.5 | Water+SSR 2.0 | AO 1.2 | Fog/volumetrics
1.0 | Bloom 0.6 | Post 1.0 | Headroom 3.3. The pack declares `[budget] gpu_ms` and the overlay flags a
pack over it.

## 5. What the pack can and cannot reach (the key constraint)

The shader API is fixed: a pack provides `[sky]`, `[material]` and up to 8 `[[post]]` full-screen
passes, each at the world's resolution, reading `scene_color`, `scene_depth`, `previous` and two
samplers plus `Frame`. A pack **cannot** choose a pass resolution, add a real cascaded shadow map, an
SSR buffer, a clustered light list, a cloud render target, a geometry buffer, or a material pass for
the hand and entities. Those are engine features.

**This fork's launcher ships the launcher only** (`launcher-fork-build.yml` builds `launcher/**` and a
fixed crate list; `launcher/src/backend.rs` installs the **game** from `GAME_REPO =
horizon-rust/horizon`). So an engine change made in this fork would **not reach a player** through a
launcher release. That splits the fix list into:

- **Reachable here (pack):** moonlight direction and phase on the material stage, sky-coloured night
  ambient, blue shadow lift and adaptive night exposure in the grade, dusk/dawn warm light and no
  pops, water at night (moon glint, Fresnel, depth colour), star fade and cloud attenuation in the sky
  stage, cloud light in the sky stage, an emissive lift, fewer bloom/AO taps, a cheaper sky stage, and
  a "Night quality" preset set with a commented settings file.
- **Needs the engine (upstream PR or a fork game build):** half-resolution bloom/AO/fog/clouds with
  temporal reuse and a depth-aware upsample, real cascaded moon shadows reusing the sun's shadow map,
  SSR with a sky fallback, a clustered/tiled light list, per-light flicker and coloured bounce,
  lighting the hand and entities with the material stage, moon phase in `Frame`, and per-pass timings
  for the engine's own passes.

The engine already has the *ingredients* the fix list asks for: a shadow-map pass with a shadow camera
(`pack_shadow.rs`, `shadow_visible`, `shadow_runs`), dynamic lights (`dynamic_light.rs`, `MAX = 16`,
already in `terrain.wgsl`), a TAA/history path (`world_post.wgsl`), and HDR output. Wiring them for
night is an engine change, not a pack change.

## 6. Ranked fixes

| # | Fix | Where | Expected effect | Cost |
|---|---|---|---|---|
| 1 | Fewer bloom taps (24 -> ~12) and an optional wide ring | pack | the biggest pack pass shrinks; ~0.3-0.5 ms at 1080p | softer bloom |
| 2 | Fewer AO taps (10 -> 6), skip AO on the far plane | pack | ~0.2-0.4 ms | softer AO |
| 3 | Cheaper sky stage: one cloud octave by default, math early-outs | pack | ~0.1-0.2 ms on sky pixels | softer clouds |
| 4 | Moonlight directional on the material stage (phase-scaled), sky night ambient | pack | the headline visual fix; no extra passes | none |
| 5 | Night tone: blue shadow lift, adaptive exposure, night-vision desaturation (grade) | pack | readable night, no crush | none |
| 6 | Dusk/dawn warm light, rim, smooth sun->twilight->moon blend (no pops) | pack | golden hour on the land | none |
| 7 | Water at night: moon glint, Fresnel, depth colour, less saturation | pack | water stops glowing | none |
| 8 | Star fade by sun elevation and cloud/moon attenuation; moon glow in the sky stage | pack | stars appear at the right time | none |
| 9 | Emissive lift so lava/torches read as self-lit | pack (post) | brighter lights at night | none |
| 10 | "Night quality" presets (Low/Medium/High/Ultra) + a commented settings file | pack | controllable cost | none |
| 11 | Half-resolution bloom/grade/AO/fog with a depth-aware upsample | **engine** | the big structural saving | upstream |
| 12 | Real cascaded moon shadows reusing the sun map, 2 cascades at night | **engine** | soft long moon shadows | upstream |
| 13 | SSR for water with sky/moon fallback, fade at edges | **engine** | true reflections | upstream |
| 14 | Half-res clouds with temporal reuse | **engine** | big cloud cost cut | upstream |
| 15 | Clustered light list, flicker, coloured bounce | **engine** | many torches cheap | upstream |
| 16 | Light the hand and entities with the material stage | **engine** | held item lit | upstream |
| 17 | Moon phase in `Frame`; per-pass engine timings | **engine** | convenience | upstream |

## 7. Fixes 1-10 implemented here

See the pack `crates/horizon-shader-api/packs/horizon_complementary` (version 1.3.0). The engine-side
list (11-17) is written up in `docs/shader-night-quality-engine.md` for the optimization-mod note and
an upstream PR; it is not silently dropped.

// The sky along each view ray: a bright sun with a wide glow, a sun-side horizon that reddens at
// sunrise and sunset, a deeper blue overhead, a moon with a soft glow at night, a cloud deck lit by
// the moon and warm at dusk, and only a little haze where the sky meets the ground. Vanilla draws
// the sun, moon and stars over this, so the glow is built to sit under them.
override sun_glow: f32 = 0.9;
override moon_glow_amount: f32 = 0.8;
override clouds: bool = true;
override fog: bool = true;
override fog_amount: f32 = 0.12;
override warmth: f32 = 0.28;
override performance_mode: bool = false;
override cloud_quality: i32 = 2;
override night_quality: u32 = 1;

fn sky(input: SkyInput) -> vec4<f32> {
    let d = input.direction;
    let day = daylight();
    let low = sun_low();
    let twi = twilight();
    let n = night();
    let clear = 1.0 - frame.rain;
    let overworld = frame.dimension == 0;
    var color = select(input.color.rgb, cr_sky(d), overworld);

    // The sun: a small hot core, a tight bloom and a wide, soft halo. The core is wide enough to
    // read as a disc under vanilla's sprite, the halo is what makes the sky look lit.
    let toward = max(dot(d, frame.sun_direction), 0.0);
    let core = pow(toward, 90.0) * 1.4 + pow(toward, 20.0) * 0.5;
    let halo = pow(toward, 4.0) * 0.45 + pow(toward, 1.4) * 0.12;
    let sun = sun_color() * (core + halo) * day * clear;
    color += sun * sun_glow * mix(0.55, 1.2, low);

    // The horizon reddens and brightens on the sun's side as it sets.
    let band = 1.0 - smoothstep(0.0, 0.22, abs(d.y));
    let hd = normalize(vec2<f32>(d.x, d.z) + vec2<f32>(1e-4));
    let hs = normalize(vec2<f32>(frame.sun_direction.x, frame.sun_direction.z) + vec2<f32>(1e-4));
    let side = max(dot(hd, hs), 0.0);
    let red = mix(vec3<f32>(1.0), vec3<f32>(1.22, 0.86, 0.6), side);
    color = mix(color, color * red, band * low * day * clear * 0.85);

    // Overhead a touch deeper and cooler, so the halo and horizon read brighter.
    let zenith = smoothstep(0.05, 0.95, d.y);
    color = mix(color, color * vec3<f32>(0.66, 0.8, 1.16), zenith * day * 0.7);

    // The moon: a small hot core and a wide soft halo, brightest on a clear night, so it reads as a
    // lit moon under vanilla's sprite instead of a hard block.
    let toward_moon = max(dot(d, frame.moon_direction), 0.0);
    color += moon_color() * moon_glow(toward_moon, 1.0) * n * clear * moon_glow_amount;

    // A faint band of light around the moon's side of the sky, so night is not flat black.
    color += moon_color() * pow(max(dot(normalize(vec3<f32>(d.x, 0.0, d.z) + vec3<f32>(1e-4)),
        normalize(vec3<f32>(frame.moon_direction.x, 0.0, frame.moon_direction.z) + vec3<f32>(1e-4))), 0.0), 3.0)
        * band * n * 0.05 * clear;

    if clouds {
        let detail = cloud_quality >= 2 && night_quality >= 1u;
        // The cover fades out well above the horizon: the overhead-plane projection blows up as the
        // ray flattens, which is what streaks down the sky at the horizon. Fading it first fixes
        // that at the source.
        let horizon = smoothstep(0.02, 0.24, d.y);
        let cover = cloud_cover(d, detail && d.y > 0.12) * horizon * clear;
        // Base cloud colour: near-black by night, white by day, with the moon's blue at night.
        let base = mix(mix(vec3<f32>(0.05, 0.07, 0.12), vec3<f32>(0.99, 0.98, 0.96), day), moon_color() * 0.35, n * 0.7);
        // Dusk and dawn: the cloud undersides glow warm toward the sun.
        let dusk = mix(base, sun_color() * 0.9, twi * 0.7);
        // The sun (or, at night, the moon) lights the cloud's near side.
        let lit_by = select(frame.moon_direction, frame.sun_direction, day > 0.5);
        let toward_lit = max(dot(d, lit_by), 0.0);
        let rim = pow(toward_lit, 3.0);
        let light_col = mix(sun_color(), moon_color() * 0.7, n);
        let lit = mix(dusk, light_col, clamp((low * day * warmth * 2.6 + n * 0.5) * (0.4 + 0.6 * toward_lit), 0.0, 0.9));
        color = mix(color, lit * (0.55 + 0.45 * toward_lit) + light_col * rim * 0.25, cover * 0.9);
    }

    // Haze: only a little, and only low, so the horizon softens without the whole view washing out.
    // It blends toward the sky's own colour so the horizon never goes flat.
    if fog {
        // A thin band right at the horizon, no more: a wide haze flattened the sky.
        let haze = (1.0 - smoothstep(0.0, 0.07, abs(d.y))) * (0.1 + 0.2 * frame.rain) * fog_amount;
        let tint = mix(frame.sky_color, mix(frame.fog_color, frame.fog_color * sun_tint(), min(low * day * clear, 1.0) * 0.7), 0.4);
        color = mix(color, select(tint, to_linear(tint), overworld), haze);
    }

    if overworld {
        color = cr_tonemap(color);
    }

    // A one-bit dither removes the banding a smooth gradient shows on 8-bit output.
    color += vec3<f32>((hash21(d.xz * 512.0) - 0.5) * (1.0 / 255.0));
    return vec4<f32>(max(color, vec3<f32>(0.0)), input.color.a);
}

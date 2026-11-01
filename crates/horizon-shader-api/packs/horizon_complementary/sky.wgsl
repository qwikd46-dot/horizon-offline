// The sky along each view ray: a warm halo around a low sun, a deeper blue overhead by day,
// moonlight haze at night, a drifting cloud layer and haze where the horizon meets the fog.
// The sun, moon, stars and vanilla's own clouds are drawn over the result.
override clouds: bool = true;
override fog: bool = true;
override warmth: f32 = 0.28;
override performance_mode: bool = false;

fn sky(input: SkyInput) -> vec4<f32> {
    let d = input.direction;
    let day = daylight();
    let low = sun_low();
    let clear = 1.0 - frame.rain;
    var color = input.color.rgb;

    // The halo: brightest toward the sun, strongest while it sits near the horizon.
    let toward = max(dot(d, frame.sun_direction), 0.0);
    let halo = pow(toward, 8.0) * 0.8 + (1.0 - smoothstep(0.0, 0.45, abs(d.y))) * toward * 0.5;
    color += vec3<f32>(1.0, 0.52, 0.22) * halo * low * day * warmth * clear;

    // Overhead: a touch cooler and deeper by day, so the halo stands out.
    let zenith = smoothstep(0.05, 0.95, d.y);
    color = mix(color, color * vec3<f32>(0.72, 0.84, 1.12), zenith * day * 0.55);

    // Night: a faint blue glow around the moon instead of a flat black sky.
    let toward_moon = max(dot(d, frame.moon_direction), 0.0);
    color += vec3<f32>(0.06, 0.09, 0.16) * pow(toward_moon, 20.0) * night() * clear;

    if clouds {
        let cover = cloud_cover(d, !performance_mode) * clear;
        // Lit from the sun side by day, a dim slate by night.
        let lit = mix(vec3<f32>(0.09, 0.11, 0.15), vec3<f32>(1.0, 0.97, 0.93), day);
        let warm = mix(lit, vec3<f32>(1.0, 0.72, 0.45), low * day * warmth * 2.0);
        color = mix(color, warm * (0.75 + 0.25 * toward), cover * 0.85);
    }

    // Haze where the sky meets the ground, in vanilla's fog colour so the terrain's own fog
    // starts from the same tone.
    if fog {
        let band = (1.0 - smoothstep(0.0, 0.22, abs(d.y))) * (0.35 + 0.4 * frame.rain);
        color = mix(color, frame.fog_color, band * 0.5);
    }

    return vec4<f32>(max(color, vec3<f32>(0.0)), input.color.a);
}

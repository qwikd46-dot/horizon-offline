// The sky along each view ray: a warm, forward-scattering halo around the sun, a deeper blue
// overhead by day, a faint moonlight glow at night, a drifting two-octave cloud deck and haze
// where the sky meets the ground. Vanilla draws the sun, moon, stars and its own clouds over
// the result.
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

    // Forward scattering: the closer the ray is to the sun, the more it glows. A tight core
    // and a wide wash, strongest while the sun sits low.
    let toward = max(dot(d, frame.sun_direction), 0.0);
    let sun = sun_tint() * (pow(toward, 16.0) * 0.9 + pow(toward, 3.0) * 0.35) * day * clear;
    color += sun * mix(0.5, 1.15, low) * warmth * 1.4;

    // The horizon reddens on the sun's side at sunrise and sunset.
    let band = 1.0 - smoothstep(0.0, 0.22, abs(d.y));
    let hd = normalize(vec2<f32>(d.x, d.z) + vec2<f32>(1e-4));
    let hs = normalize(vec2<f32>(frame.sun_direction.x, frame.sun_direction.z) + vec2<f32>(1e-4));
    let side = max(dot(hd, hs), 0.0);
    let red = mix(vec3<f32>(1.0), vec3<f32>(1.18, 0.92, 0.72), side);
    color = mix(color, color * red, band * low * day * clear * 0.7);

    // Overhead: a touch cooler and deeper by day, so the halo stands out.
    let zenith = smoothstep(0.05, 0.95, d.y);
    color = mix(color, color * vec3<f32>(0.7, 0.83, 1.14), zenith * day * 0.6);

    // Night: a faint blue glow around the moon instead of a flat black sky.
    let toward_moon = max(dot(d, frame.moon_direction), 0.0);
    color += vec3<f32>(0.05, 0.08, 0.15) * pow(toward_moon, 24.0) * night() * clear;

    if clouds {
        let cover = cloud_cover(d, !performance_mode) * clear;
        // Lit from the sun side by day, a dim slate by night, warm at the edges at sunset.
        let base = mix(vec3<f32>(0.07, 0.09, 0.13), vec3<f32>(0.98, 0.97, 0.95), day);
        let lit = mix(base, sun_tint(), min(low * day * warmth * 2.4, 0.85));
        color = mix(color, lit * (0.62 + 0.38 * toward), cover * 0.88);
    }

    if fog {
        let haze = (1.0 - smoothstep(0.0, 0.24, abs(d.y))) * (0.3 + 0.45 * frame.rain);
        // The haze takes the sun's tint on its side, so the horizon glows at sunset.
        let tint = mix(frame.fog_color, frame.fog_color * sun_tint(), min(low * day * clear, 1.0) * 0.6);
        color = mix(color, tint, haze * 0.5);
    }

    // A tiny ordered dither kills the banding a smooth gradient shows on 8-bit output.
    color += vec3<f32>((hash21(d.xz * 512.0) - 0.5) * (1.0 / 255.0));
    return vec4<f32>(max(color, vec3<f32>(0.0)), input.color.a);
}

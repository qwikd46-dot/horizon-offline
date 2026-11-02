// The sky along each view ray: a bright sun with a wide glow, a sun-side horizon that reddens at
// sunrise and sunset, a deeper blue overhead, a faint moon glow at night, a drifting cloud deck
// and only a little haze where the sky meets the ground. Vanilla draws the sun, moon and stars
// over this, so the glow is built to sit under them.
override sun_glow: f32 = 1.0;
override clouds: bool = true;
override fog: bool = true;
override fog_amount: f32 = 0.35;
override warmth: f32 = 0.28;
override performance_mode: bool = false;

fn sky(input: SkyInput) -> vec4<f32> {
    let d = input.direction;
    let day = daylight();
    let low = sun_low();
    let clear = 1.0 - frame.rain;
    var color = input.color.rgb;

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

    // The moon: a small glow, brightest on a clear night.
    let toward_moon = max(dot(d, frame.moon_direction), 0.0);
    color += vec3<f32>(0.06, 0.09, 0.16) * (pow(toward_moon, 120.0) * 1.2 + pow(toward_moon, 10.0) * 0.2)
        * night() * clear;

    if clouds {
        let cover = cloud_cover(d, !performance_mode) * clear;
        let base = mix(vec3<f32>(0.07, 0.09, 0.13), vec3<f32>(0.99, 0.98, 0.96), day);
        let lit = mix(base, sun_color(), min(low * day * warmth * 2.6, 0.9));
        // Clouds catch the sun's glow on their sunward side.
        color = mix(color, lit * (0.6 + 0.4 * toward), cover * 0.9);
    }

    // Haze: only a little, and only low, so the horizon softens without the whole view washing out.
    if fog {
        let haze = (1.0 - smoothstep(0.0, 0.14, abs(d.y))) * (0.18 + 0.3 * frame.rain) * fog_amount;
        let tint = mix(frame.fog_color, frame.fog_color * sun_tint(), min(low * day * clear, 1.0) * 0.7);
        color = mix(color, tint, haze);
    }

    // A one-bit dither removes the banding a smooth gradient shows on 8-bit output.
    color += vec3<f32>((hash21(d.xz * 512.0) - 0.5) * (1.0 / 255.0));
    return vec4<f32>(max(color, vec3<f32>(0.0)), input.color.a);
}

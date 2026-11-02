// The final grade: exposure, a filmic curve (or a softer shoulder), golden light while the sun is
// low, a blue shadow lift and a slow night exposure so the dark stays readable without crushing to
// black, cool shadows, mid-tone contrast, saturation and an optional vignette. The order is chosen
// so nothing clips before the curve and the tint shifts hue without crushing detail.
override exposure: f32 = 1.05;
override filmic: bool = true;
override contrast: f32 = 1.08;
override saturation: f32 = 1.18;
override warmth: f32 = 0.28;
override vignette: bool = false;
override night_exposure: f32 = 0.22;
override shadow_lift: f32 = 0.05;
override night_desaturate: f32 = 0.3;

// Narkowicz's ACES fit: highlights roll off instead of clipping, and white stays white.
fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp(x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn post(input: PostInput) -> vec4<f32> {
    let n = night();
    let twi = twilight();
    // A slow night exposure: the whole picture lifts as the sun sets, following `night()`, which is
    // a smoothstep, so it never flickers or pops. Highlights are held by the filmic curve below.
    let night_gain = 1.0 + n * night_exposure;
    var c = max(input.color.rgb, vec3<f32>(0.0)) * exposure * night_gain;
    if filmic {
        c = aces(c);
    } else {
        // A gentler shoulder: a quarter of a Reinhard curve, undone so mid-tones keep their
        // brightness.
        c = c / (1.0 + 0.25 * c) * 1.25;
    }

    // Golden light once the curve is applied, so the tint shifts hue without crushing detail.
    let golden = warmth * mix(0.25, 1.0, sun_low()) * daylight() * (1.0 - frame.rain * 0.7);
    c *= mix(vec3<f32>(1.0), vec3<f32>(1.12, 1.0, 0.82), min(golden, 1.0));

    // A blue-tinted shadow lift: the darkest tones move up toward the moon's colour at night, so
    // albedo and detail survive instead of crushing to black. The lift fades with brightness, so
    // lit surfaces keep their contrast.
    let shadow = 1.0 - smoothstep(0.0, 0.5, luminance(c));
    c += moon_color() * shadow * n * shadow_lift;
    c += vec3<f32>(-0.012, 0.0, 0.03) * shadow;

    // Human night vision: dark regions desaturate a little and shift blue, but the greens stay
    // readable and nothing flattens to grey.
    let dark = 1.0 - smoothstep(0.0, 0.35, luminance(c));
    c = mix(c, saturate(c, 0.65) * vec3<f32>(0.92, 1.0, 1.14), dark * n * night_desaturate);

    // Contrast around mid grey, then saturation around each pixel's own luminance.
    c = (c - 0.5) * contrast + 0.5;
    c = saturate(c, saturation);

    if vignette {
        let aspect = frame.resolution.x / max(frame.resolution.y, 1.0);
        let d = length((input.uv - 0.5) * vec2<f32>(aspect, 1.0)) / length(vec2<f32>(aspect, 1.0) * 0.5);
        c *= 1.0 - smoothstep(0.55, 1.1, d) * 0.3;
    }
    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}

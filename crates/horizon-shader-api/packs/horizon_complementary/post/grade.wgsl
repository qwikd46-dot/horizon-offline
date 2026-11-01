// The final grade: exposure, a filmic curve (or a softer shoulder), golden light while the sun
// is low, mid-tone contrast, saturation and an optional vignette.
override exposure: f32 = 1.05;
override filmic: bool = true;
override contrast: f32 = 1.08;
override saturation: f32 = 1.18;
override warmth: f32 = 0.28;
override vignette: bool = false;

// Narkowicz's ACES fit: highlights roll off instead of clipping, and white stays white.
fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp(x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn post(input: PostInput) -> vec4<f32> {
    var c = max(input.color.rgb, vec3<f32>(0.0)) * exposure;
    if filmic {
        c = aces(c);
    } else {
        // A gentler shoulder: a quarter of a Reinhard curve, undone so mid-tones keep their
        // brightness.
        c = c / (1.0 + 0.25 * c) * 1.25;
    }
    // Golden light once the curve is applied, so the tint shifts hue without crushing detail.
    let golden = warmth * mix(0.25, 1.0, sun_low()) * daylight() * (1.0 - frame.rain * 0.7);
    c *= mix(vec3<f32>(1.0), vec3<f32>(1.1, 1.0, 0.84), min(golden, 1.0));
    // Contrast around mid grey, then saturation around each pixel's own luminance.
    c = (c - 0.5) * contrast + 0.5;
    c = mix(vec3<f32>(luminance(c)), c, saturation);
    if vignette {
        let aspect = frame.resolution.x / max(frame.resolution.y, 1.0);
        let d = length((input.uv - 0.5) * vec2<f32>(aspect, 1.0)) / length(vec2<f32>(aspect, 1.0) * 0.5);
        c *= 1.0 - smoothstep(0.55, 1.1, d) * 0.3;
    }
    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}

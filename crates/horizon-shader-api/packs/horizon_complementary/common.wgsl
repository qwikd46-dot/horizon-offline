// Shared by every stage of the pack. Small and branch-light, so a stage pays only for what it
// calls. No bindings and no texture reads: sky, material and post can all use them.

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Saturation around the colour's own luminance (1 keeps it, 0 is grey).
fn saturate(c: vec3<f32>, amount: f32) -> vec3<f32> {
    return mix(vec3<f32>(luminance(c)), c, amount);
}

// 1 while the sun is up, easing out through the horizon. 0 outside the Overworld.
fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.08, 0.14, frame.sun_direction.y), frame.dimension == 0);
}

// 1 at night, 0 by day.
fn night() -> f32 {
    return select(0.0, 1.0 - smoothstep(-0.22, 0.04, frame.sun_direction.y), frame.dimension == 0);
}

// 1 with the sun on the horizon, 0 a third of the way up: sunrise and sunset.
fn sun_low() -> f32 {
    return 1.0 - smoothstep(0.0, 0.3, abs(frame.sun_direction.y));
}

// The sun's own tint: white high up, amber to red as it sets, dimmed by rain.
fn sun_tint() -> vec3<f32> {
    let low = sun_low();
    let warm = mix(vec3<f32>(1.0, 0.96, 0.9), vec3<f32>(1.0, 0.5, 0.24), low);
    return mix(warm, vec3<f32>(1.0, 0.62, 0.34), low * low * 0.5) * (1.0 - frame.rain * 0.5);
}

// A cheap 2D hash in 0..1, for the cloud layer and the dither.
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise in 0..1: four hashes, no texture read.
fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// How much cloud covers a view ray: a drifting layer on a plane overhead, none below the
// horizon. `detail` adds a finer, rotated octave (what performance mode drops).
fn cloud_cover(d: vec3<f32>, detail: bool) -> f32 {
    let up = max(d.y, 0.05);
    let wind = 1.0 + frame.rain * 2.5;
    let drift = vec2<f32>(frame.time * 0.005, frame.time * 0.002) * wind;
    let p = d.xz / up * 1.4 + drift;
    var n = noise2(p);
    if detail {
        // The second octave is rotated off the axes, so the sampling grid never shows.
        let q = vec2<f32>(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8) * 3.03;
        n = n * 0.7 + noise2(q) * 0.3;
    }
    // Denser and lower when it rains.
    return smoothstep(0.52 - frame.rain * 0.18, 0.82 - frame.rain * 0.2, n) * smoothstep(0.0, 0.13, d.y);
}

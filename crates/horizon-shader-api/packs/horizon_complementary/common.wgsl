// Shared by every stage of the pack. Kept to small, branch-light helpers so a stage pays
// only for what it calls.

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// 1 while the sun is up in the Overworld, easing out around the horizon.
fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.06, 0.12, frame.sun_direction.y), frame.dimension == 0);
}

// 1 at night, 0 by day.
fn night() -> f32 {
    return select(0.0, 1.0 - smoothstep(-0.2, 0.05, frame.sun_direction.y), frame.dimension == 0);
}

// 1 with the sun on the horizon, 0 a third of the way up: sunrise and sunset.
fn sun_low() -> f32 {
    return 1.0 - smoothstep(0.0, 0.32, abs(frame.sun_direction.y));
}

// A cheap 2D hash in 0..1, for the cloud layer.
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.545);
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

// How much cloud covers a view ray: a drifting layer on a plane overhead, no clouds below the
// horizon or inside it.
fn cloud_cover(d: vec3<f32>, detail: bool) -> f32 {
    let up = max(d.y, 0.06);
    let drift = vec2<f32>(frame.time * 0.004, frame.time * 0.0015);
    let p = d.xz / up * 1.5 + drift;
    var n = noise2(p);
    if detail {
        // The second, finer octave is what performance mode drops.
        n = n * 0.7 + noise2(p * 3.1) * 0.3;
    }
    return smoothstep(0.5, 0.8, n) * smoothstep(0.0, 0.14, d.y);
}

// Shared helpers for every stage of the pack. Small, branch-light and free of texture reads, so a
// stage pays only for what it calls and sky, material and post can all share them.

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn saturate(c: vec3<f32>, amount: f32) -> vec3<f32> {
    return mix(vec3<f32>(luminance(c)), c, amount);
}

// 1 while the sun is up, easing through the horizon. 0 outside the Overworld.
fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.08, 0.14, frame.sun_direction.y), frame.dimension == 0);
}

// 1 at night, 0 by day. The ramp is wide so dusk and dawn blend, never pop.
fn night() -> f32 {
    return select(0.0, 1.0 - smoothstep(-0.24, 0.02, frame.sun_direction.y), frame.dimension == 0);
}

// 1 with the sun on the horizon, 0 a third of the way up: sunrise and sunset.
fn sun_low() -> f32 {
    return 1.0 - smoothstep(0.0, 0.32, abs(frame.sun_direction.y));
}

// 1 near sunrise or sunset and 0 a quarter of the way up, on both sides: the golden hour, whether
// the sun is rising or setting.
fn twilight() -> f32 {
    return select(0.0, smoothstep(0.30, 0.02, abs(frame.sun_direction.y)), frame.dimension == 0);
}

// How high the moon is: 0 below the horizon, 1 well up. The moonlight follows it.
fn moon_up() -> f32 {
    return select(0.0, smoothstep(-0.06, 0.22, frame.moon_direction.y), frame.dimension == 0);
}

// The sun's own tint: white high up, amber to red as it sets, dimmed by rain.
fn sun_tint() -> vec3<f32> {
    let low = sun_low();
    let warm = mix(vec3<f32>(1.0, 0.96, 0.9), vec3<f32>(1.0, 0.5, 0.24), low);
    return mix(warm, vec3<f32>(1.0, 0.62, 0.34), low * low * 0.5) * (1.0 - frame.rain * 0.5);
}

// The sun's colour at full strength, before rain dims it: what a specular highlight takes.
fn sun_color() -> vec3<f32> {
    let low = sun_low();
    return mix(vec3<f32>(1.0, 0.97, 0.9), vec3<f32>(1.0, 0.55, 0.28), low * low);
}

// The moon's colour: a cool blue-white, what the world takes on a clear night.
fn moon_color() -> vec3<f32> {
    return vec3<f32>(0.45, 0.55, 0.85);
}

// The night sky's ambient: a deep blue, stronger overhead than from below, with a faint warm ground
// bounce so shadows are not flat. `upness` is the surface normal's y (-1 down, 1 up).
fn night_ambient(upness: f32) -> vec3<f32> {
    let sky = vec3<f32>(0.16, 0.24, 0.5);
    let ground = vec3<f32>(0.09, 0.08, 0.1);
    return mix(ground, sky, clamp(upness * 0.5 + 0.5, 0.0, 1.0));
}

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

// How much cloud covers a view ray: a drifting layer on a plane overhead, none below the horizon.
// `detail` adds a finer, rotated octave (what the lower quality presets drop).
fn cloud_cover(d: vec3<f32>, detail: bool) -> f32 {
    let up = max(d.y, 0.05);
    let wind = 1.0 + frame.rain * 2.5;
    let drift = vec2<f32>(frame.time * 0.005, frame.time * 0.002) * wind;
    let p = d.xz / up * 1.4 + drift;
    var n = noise2(p);
    if detail {
        let q = vec2<f32>(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8) * 3.03;
        n = n * 0.7 + noise2(q) * 0.3;
    }
    return smoothstep(0.52 - frame.rain * 0.18, 0.82 - frame.rain * 0.2, n) * smoothstep(0.0, 0.13, d.y);
}

// A water surface normal from a slow swell and two crossing chop waves. Each term is one travelling
// sine, and their directions and speeds are all different, so the crests drift instead of settling
// into a repeating grid. The gradient is analytic, so this is a few cosines and no texture read.
// `amplitude` 0 is flat water.
fn wave_normal(p: vec2<f32>, amplitude: f32, scale: f32, speed: f32) -> vec3<f32> {
    let t = frame.time * speed;
    let k1 = vec2<f32>(0.66, 0.75) * scale * 0.9;
    let k2 = vec2<f32>(-0.62, 0.78) * scale * 1.9;
    let k3 = vec2<f32>(0.18, -0.98) * scale * 3.2;
    let dx = k1.x * cos(dot(k1, p) + t) + k2.x * cos(dot(k2, p) - t * 1.15)
        + k3.x * cos(dot(k3, p) + t * 1.7);
    let dz = k1.y * cos(dot(k1, p) + t) + k2.y * cos(dot(k2, p) - t * 1.15)
        + k3.y * cos(dot(k3, p) + t * 1.7);
    return normalize(vec3<f32>(-dx * amplitude, 1.0, -dz * amplitude));
}

// Blinn-Phong specular, the standard cheap highlight.
fn specular(n: vec3<f32>, view: vec3<f32>, light: vec3<f32>, power: f32) -> f32 {
    let h = normalize(light + view);
    return pow(max(dot(n, h), 0.0), power);
}

// Schlick's approximation of Fresnel: 0 facing the surface, 1 at a grazing angle.
fn fresnel(view: vec3<f32>, n: vec3<f32>, power: f32) -> f32 {
    return pow(1.0 - max(dot(view, n), 0.0), power);
}

// The moon disc and its soft glow along a view ray: a small core, a wide halo, so it reads as a lit
// moon under vanilla's sprite instead of a hard rectangle. `size` widens the core.
fn moon_glow(toward: f32, size: f32) -> f32 {
    let core = pow(toward, 900.0 / size) * 1.6;
    let tight = pow(toward, 90.0 / size) * 0.5;
    let halo = pow(toward, 12.0 / size) * 0.22 + pow(toward, 3.0 / size) * 0.05;
    return core + tight + halo;
}

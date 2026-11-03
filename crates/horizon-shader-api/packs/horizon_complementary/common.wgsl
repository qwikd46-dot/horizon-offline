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


// ---- Complementary Reimagined (r5.9.3) palette and tonemap, ported to WGSL -----------------------
// The frame the pack draws into is in vanilla's gamma space, so every colour below is computed in
// linear light, tonemapped once (cr_tonemap) and handed back gamma-encoded. Nothing downstream
// applies a second curve.
override tm_exposure: f32 = 1.0;
override tm_contrast: f32 = 1.05;
override tm_white_path: f32 = 1.0;
override tm_dark_desat: f32 = 0.25;

fn to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    let k = vec3<f32>(0.055);
    let hi = (vec3<f32>(1.0) + k) * pow(max(c, vec3<f32>(1e-6)), vec3<f32>(1.0 / 2.4)) - k;
    return select(hi, 12.92 * c, c < vec3<f32>(0.0031308));
}

// Lottes' tonemap as Complementary modifies it: a contrast curve with a roll-off, a path to white,
// the dark colours left readable and desaturated a little. Linear in, gamma out.
fn cr_tonemap(input_color: vec3<f32>) -> vec3<f32> {
    let color = max(input_color, vec3<f32>(0.0)) * tm_exposure;
    let initial = luminance(color);
    let a = tm_contrast;
    let hdr_max = pow(8.0, a);
    let mid_in = pow(0.25, a);
    let mid_out = 0.25;
    let denom = (hdr_max - mid_in) * mid_out;
    let b = (hdr_max * mid_out - mid_in) / denom;
    let cc = (hdr_max * mid_in - hdr_max * mid_out * mid_in) / denom;
    let pa = pow(max(color, vec3<f32>(1e-6)), vec3<f32>(a));
    var out = linear_to_srgb(pa / (pa * b + cc));

    let dark_lift = smoothstep(0.1, 0.0, initial);
    let smooth_color = pow(max(color, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
    out = mix(out, smooth_color, dark_lift * 0.75 * max(0.55 - abs(1.05 - tm_contrast), 0.0) / 0.55);

    let modified = pow(initial / 16.0, 2.0 - tm_white_path) * 16.0;
    out = mix(out, vec3<f32>(1.0), smoothstep(0.0, 16.0, modified));

    let desat = smoothstep(0.1, 0.0, initial);
    out = mix(out, vec3<f32>(luminance(out)), desat * tm_dark_desat);
    return clamp(out, vec3<f32>(0.0), vec3<f32>(1.0));
}

// Complementary's noonFactor, sunVisibility2 and sunFactor from the sun's height.
fn cr_noon() -> f32 {
    return sqrt(max(frame.sun_direction.y, 0.0));
}

fn cr_sun_vis2() -> f32 {
    let v = clamp(frame.sun_direction.y + 0.0625, 0.0, 0.125) / 0.125;
    return v * v;
}

fn cr_sun_factor() -> f32 {
    let s = frame.sun_direction.y;
    return select(clamp(s + 0.03125, 0.0, 0.0625) / 0.0625, clamp(s + 0.375, 0.0, 0.75) / 0.75, s < 0.0);
}

// Direct light colour on the ground: noon, sunset, night, rain (lightAndAmbientColors.glsl).
fn cr_light_color() -> vec3<f32> {
    let noon = cr_noon();
    let inv_noon = 1.0 - noon;
    let vis = cr_sun_vis2();
    let b = frame.brightness;
    let noon_c = vec3<f32>(0.65, 0.55, 0.375) * 2.05;
    let sunset_c = pow(vec3<f32>(0.64, 0.45, 0.3), vec3<f32>(1.5 + inv_noon)) * 5.0;
    let night_c = 0.9 * vec3<f32>(0.15, 0.14, 0.20) * (0.4 + b * 0.4);
    let clear_c = mix(night_c, mix(sunset_c, noon_c, noon), vis);
    let day_rain = vec3<f32>(0.21, 0.16, 0.13) * 0.85 + noon * vec3<f32>(0.0, 0.02, 0.06);
    let night_rain = vec3<f32>(0.03, 0.035, 0.05) * (0.5 + 0.5 * b);
    let rain_c = mix(night_rain, day_rain * 0.6, vis) * 2.5;
    return mix(clear_c, rain_c, frame.rain);
}

// Ambient (sky) light colour.
fn cr_ambient_color() -> vec3<f32> {
    let noon = cr_noon();
    let vis = cr_sun_vis2();
    let b = frame.brightness;
    let noon_a = pow(max(frame.sky_color, vec3<f32>(0.0)), vec3<f32>(0.75)) * 0.85;
    let sunset_a = noon_a * vec3<f32>(1.21, 0.92, 0.76) * 0.95;
    let night_a = 0.9 * vec3<f32>(0.09, 0.12, 0.17) * (1.55 + b * 0.77);
    let clear_a = mix(night_a, mix(sunset_a, noon_a, noon), vis);
    let day_rain = vec3<f32>(0.2, 0.2, 0.25) * (1.8 + 0.5 * b);
    let night_rain = vec3<f32>(0.16, 0.20, 0.3) * (0.75 + 0.6 * b);
    let rain_a = mix(night_rain, day_rain * 1.4, vis);
    return mix(clear_a, rain_a, frame.rain);
}

// The sky's colour along a ray: Complementary's up / middle / down gradient for noon, sunset and
// night (skyColors.glsl), linear and untonemapped.
fn cr_sky(d: vec3<f32>) -> vec3<f32> {
    let rain = frame.rain;
    let rain2 = rain * rain;
    let inv_r2 = (1.0 - rain) * (1.0 - rain);
    let sc = max(frame.sky_color, vec3<f32>(0.0));
    let scs = sqrt(sc);
    let sky_m = mix(max(scs, vec3<f32>(0.63, 0.67, 0.73)), scs, inv_r2);
    let sky_m2 = mix(max(sc, cr_sun_factor() * vec3<f32>(0.265, 0.295, 0.35)), sc, inv_r2);
    let noon = cr_noon();
    let inv_noon2 = (1.0 - noon) * (1.0 - noon);

    let nusc = vec3<f32>(0.1, 0.0, 0.1);
    let nmsc = vec3<f32>(-0.1, -0.4, -0.6) + vec3<f32>(0.0, 0.06, 0.12) * noon;
    let ndsc = vec3<f32>(-0.15, -0.3, -0.42) + vec3<f32>(0.0, 0.02, 0.08) * noon;
    let noon_up = pow(sky_m, vec3<f32>(2.9)) * (vec3<f32>(0.85, 0.92, 0.81) + rain * nusc);
    let noon_mid = sky_m * (vec3<f32>(1.4, 1.3, 1.3) + rain * nmsc) + noon_up * 0.25;
    let noon_down = sky_m * (vec3<f32>(0.9) + rain * ndsc) + noon_up * 0.25;

    let sun_up = sky_m2 * (vec3<f32>(0.72, 0.522, 0.47) + vec3<f32>(0.1, 0.2, 0.35) * rain2);
    let sun_mid = sky_m2 * (vec3<f32>(1.8, 1.3, 1.2) + vec3<f32>(0.15, 0.25, -0.05) * rain2);
    let sun_down = (vec3<f32>(1.45, 0.86, 0.5) - vec3<f32>(0.8, 0.3, 0.0) * rain) * 0.5 + 0.25 * sun_mid;

    let day_up = mix(noon_up, sun_up, inv_noon2);
    let day_mid = mix(noon_mid, sun_mid, inv_noon2);
    let day_down = mix(noon_down, sun_down, inv_noon2);

    let ncf = 0.9 * vec3<f32>(0.07, 0.14, 0.24) * (1.0 - 0.5 * rain) + sc;
    let night_up = pow(ncf, vec3<f32>(0.9)) * 0.45;
    let night_mid = sqrt(night_up) * 0.65;
    let night_down = night_mid * vec3<f32>(0.82, 0.82, 0.88);

    let vis = cr_sun_vis2();
    let up = mix(night_up, day_up, vis);
    let mid = mix(night_mid, day_mid, vis);
    let down = mix(night_down, day_down, vis);

    var col = mix(mid, up, smoothstep(0.0, 0.75, d.y));
    col = mix(col, down, smoothstep(0.0, 0.35, -d.y));
    return col;
}

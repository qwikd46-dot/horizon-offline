// The water surface: the Glistening Water travelling-wave field, the sun glint ("glisten") it throws
// back, the caustics the sun casts through it, the rings the rain and a swimmer leave behind, and the
// specular helper the material stage uses. Shared by the pack, so the material stage calls it and the
// sky and post stages simply do not.
//
// The wave field is a port of Glistening Water V1.1: six lake-scale Gerstner components plus three
// capillary ones, each travelling at the deep-water speed (angular frequency = sqrt(g * wave number))
// instead of a hand-picked one, so the crests move at the right rate and drift past each other instead
// of locking into a repeating grid. The normal is the exact derivative of the same field, so the shape
// and the shading agree. Horizon's material stage shades an already-built block face, so the field
// tilts the surface (its normal) rather than displacing geometry; the geometry is vanilla's water
// block. The field is anchored to the world, not the camera, so it stays put as you walk.
//
// Everything here is analytic (a handful of cosines and two hashes) and nothing samples a texture, so
// a stage pays only for what it calls.

override water: bool = true;
override water_waves: f32 = 0.5;
override water_specular: f32 = 0.6;
override water_reflect: f32 = 0.5;
override water_caustics: f32 = 0.5;
override water_ripples: f32 = 0.6;
override water_clarity: f32 = 0.75;

const GW_TAU: f32 = 6.28318530717958647692;
const GW_GRAVITY: f32 = 9.81;
// Glistening Water's WAVE_SPEED setting, at its default.
const GW_SPEED: f32 = 0.8;

// The accumulated surface: the displacement and the two tangents. Their cross product is the normal.
struct GwWave {
    offset: vec3<f32>,
    tangent_x: vec3<f32>,
    tangent_z: vec3<f32>,
}

// A large period keeps the wave coordinates small far from spawn, where a raw world coordinate would
// lose the precision that keeps neighbouring crests distinct.
fn gw_wrap(p: vec2<f32>) -> vec2<f32> {
    return p - 4096.0 * floor(p / 4096.0);
}

fn gw_zero() -> GwWave {
    return GwWave(vec3<f32>(0.0), vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, 0.0, 1.0));
}

// One travelling Gerstner component: its displacement and its exact x and z derivatives. A lower
// horizontal-to-vertical ratio (0.5) rounds the crests instead of pinching them into hard ridges.
fn gw_add_gerstner(w: ptr<function, GwWave>, position: vec2<f32>, direction: vec2<f32>,
                   wavelength: f32, amplitude: f32, speed: f32, phase_offset: f32, time: f32) {
    let dir = normalize(direction);
    let wave_number = GW_TAU / wavelength;
    let angular_frequency = sqrt(GW_GRAVITY * wave_number);
    let phase = wave_number * dot(dir, position)
        - angular_frequency * GW_SPEED * speed * time + phase_offset;
    let sine = sin(phase);
    let cosine = cos(phase);
    let horizontal = amplitude * 0.5;
    (*w).offset += vec3<f32>(dir.x * horizontal * cosine, amplitude * sine,
                             dir.y * horizontal * cosine);
    let dx = wave_number * dir.x;
    let dz = wave_number * dir.y;
    (*w).tangent_x += vec3<f32>(-dir.x * horizontal * sine * dx, amplitude * cosine * dx,
                                -dir.y * horizontal * sine * dx);
    (*w).tangent_z += vec3<f32>(-dir.x * horizontal * sine * dz, amplitude * cosine * dz,
                                -dir.y * horizontal * sine * dz);
}

// Six incommensurate wavelengths, so there is no obvious tiled beat; the energy sits on the longer
// lake-scale bands, which keeps the surface broad and gentle instead of stripe-like.
fn gw_add_wind(w: ptr<function, GwWave>, position: vec2<f32>, strength: f32, time: f32) {
    gw_add_gerstner(w, position, vec2<f32>(1.000,  0.080), 23.70, strength * 0.10, 0.58, 0.18, time);
    gw_add_gerstner(w, position, vec2<f32>(0.985,  0.220), 14.90, strength * 0.20, 0.71, 1.37, time);
    gw_add_gerstner(w, position, vec2<f32>(0.950, -0.310),  9.35, strength * 0.22, 0.84, 2.81, time);
    gw_add_gerstner(w, position, vec2<f32>(0.900,  0.430),  6.15, strength * 0.20, 0.99, 4.46, time);
    gw_add_gerstner(w, position, vec2<f32>(0.995, -0.100),  3.92, strength * 0.17, 1.14, 5.72, time);
    gw_add_gerstner(w, position, vec2<f32>(0.860,  0.510),  2.63, strength * 0.11, 1.31, 3.53, time);
}

// Very small capillary ripples break up the reflection bands without adding hard geometry.
fn gw_add_capillary(w: ptr<function, GwWave>, position: vec2<f32>, strength: f32, time: f32) {
    gw_add_gerstner(w, position, vec2<f32>(0.970,  0.260), 1.37, strength * 0.025, 1.38, 0.91, time);
    gw_add_gerstner(w, position, vec2<f32>(0.910, -0.420), 0.89, strength * 0.014, 1.56, 4.08, time);
    gw_add_gerstner(w, position, vec2<f32>(0.800,  0.600), 0.57, strength * 0.006, 1.73, 2.17, time);
}

// The water normal at a world xz. `detail` adds the capillary layer; the caller drops it with
// distance, where it is sub-pixel. `strength` 0 is flat water.
fn gw_normal(world_xz: vec2<f32>, time: f32, strength: f32, detail: bool) -> vec3<f32> {
    if strength <= 0.0 {
        return vec3<f32>(0.0, 1.0, 0.0);
    }
    var w = gw_zero();
    let position = gw_wrap(world_xz);
    gw_add_wind(&w, position, strength, time);
    if detail {
        gw_add_capillary(&w, position, strength, time);
    }
    let analytic = normalize(cross(w.tangent_z, w.tangent_x));
    return normalize(mix(vec3<f32>(0.0, 1.0, 0.0), analytic, 0.92));
}

// The glisten: how squarely the wave normal throws the sun back at the eye. Three overlapping
// finite-width lobes keep the sun's road and its brilliant centres without the sub-pixel spikes that
// pop as the camera crosses a pixel boundary.
fn gw_glisten_response(sun_alignment: f32) -> f32 {
    let a = clamp(sun_alignment, 0.0, 1.0);
    return pow(a, 72.0) * 0.28 + pow(a, 140.0) * 0.82 + pow(a, 360.0) * 0.50;
}

// One expanding ring: `sin(pi*x)` is zero at its centre and its rim and strongest between, so its
// gradient tilts the surface along the ring, crest pushing out and trough trailing. `d` is the offset
// from the ring's centre, `radius` its current size and `decay` how far through its life it is.
fn ring_slope(d: vec2<f32>, radius: f32, decay: f32, strength: f32) -> vec2<f32> {
    let r = length(d);
    if r >= radius || radius <= 1e-4 {
        return vec2<f32>(0.0, 0.0);
    }
    let x = r / radius;
    // d(sin(pi*x))/dr = pi/R * cos(pi*x): the slope of the ring.
    let slope = 3.14159265 / radius * cos(x * 3.14159265);
    let dir = select(vec2<f32>(1.0, 0.0), d / r, r > 1e-4);
    return dir * (slope * decay * strength);
}

// The rain's rings: one impact per cell of a grid in world xz, each an expanding ring whose phase
// differs per cell, so the surface is pricked all over instead of pulsing as one. `p` is the
// fragment's camera-relative xz and `strength` scales with the rain. The grid is the world's, not
// the camera's, so it stays put as you walk; the world xz is wrapped to a small period before the
// hash, because a hash of a huge coordinate loses the precision that makes the cells distinct, and
// a period the size of a few chunks is invisible on rain. Nine cells is enough: a ring's radius
// stays under a block, so only the fragment's own cell and its neighbours can reach it.
fn rain_ripples(p: vec2<f32>, strength: f32) -> vec3<f32> {
    if strength <= 0.0 {
        return vec3<f32>(0.0, 0.0, 0.0);
    }
    let world = p + frame.camera_position.xz;
    let cell = floor(world);
    let period = 64.0;
    var tilt = vec2<f32>(0.0, 0.0);
    for (var i = -1; i <= 1; i = i + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            let c = cell + vec2<f32>(f32(i), f32(j));
            // Hash the cell's index wrapped to a small period: hashing the world cell directly
            // would lose the precision that keeps neighbouring cells distinct far from spawn.
            let h = hash21(c - period * floor(c / period));
            let centre = c + vec2<f32>(h, fract(h * 7.13));
            let age = fract(frame.time * 0.85 + h * 3.7);
            let radius = age * 1.1;
            tilt += ring_slope(world - centre, radius, (1.0 - age) * (1.0 - age), strength);
        }
    }
    return vec3<f32>(-tilt.x, 0.0, -tilt.y);
}

// The rings a swimmer leaves: two rings centred on the camera, half a life apart, so the surface
// around the player is always disturbed. Only while the camera is in water (`eye_in` 1).
fn swim_ripples(p: vec2<f32>, strength: f32) -> vec3<f32> {
    if strength <= 0.0 || frame.eye_in != 1u {
        return vec3<f32>(0.0, 0.0, 0.0);
    }
    var tilt = vec2<f32>(0.0, 0.0);
    for (var i = 0u; i < 2u; i = i + 1u) {
        let age = fract(frame.time * 0.9 + f32(i) * 0.5);
        let radius = age * 2.4;
        tilt += ring_slope(p, radius, (1.0 - age) * (1.0 - age), strength);
    }
    return vec3<f32>(-tilt.x, 0.0, -tilt.y);
}

// The caustic web the sun casts onto the water: two ridged noise layers, each a bright thin line
// where the noise crosses its middle, multiplied. Cheap (no texture) and only called for water.
fn caustic_pattern(p: vec2<f32>, t: f32) -> f32 {
    let q1 = p * 0.5 + vec2<f32>(t * 0.05, -t * 0.04);
    let q2 = p * 0.9 + vec2<f32>(-t * 0.03, t * 0.06);
    let r1 = 1.0 - abs(2.0 * noise2(q1) - 1.0);
    let r2 = 1.0 - abs(2.0 * noise2(q2) - 1.0);
    let v = r1 * r2;
    return v * v;
}

// A GGX micro-facet specular term: a tighter, more believable moon highlight than a plain
// Blinn-Phong power, at the same cost. `roughness` ~0.05 is a sharp glint, higher is a broad sheen.
fn ggx_specular(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, roughness: f32) -> f32 {
    let h = normalize(v + l);
    let ndl = max(dot(n, l), 0.0);
    let ndv = max(dot(n, v), 1e-4);
    let ndh = max(dot(n, h), 0.0);
    let a = max(roughness * roughness, 1e-3);
    let a2 = a * a;
    let d = a2 / (3.14159265 * pow(ndh * ndh * (a2 - 1.0) + 1.0, 2.0));
    let k = a * 0.5;
    let g = (ndv / (ndv * (1.0 - k) + k)) * (ndl / (ndl * (1.0 - k) + k));
    return d * g / (4.0 * ndv * ndl + 1e-4);
}

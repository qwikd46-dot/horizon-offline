// The water surface: a travelling-wave field, the caustics the sun casts through it, the rings the
// rain and a swimmer leave behind, and the specular helpers the material stage uses. Shared by the
// pack, so the material stage calls it and the sky and post stages simply do not. Every wave is
// analytic (a few cosines), the rings are procedural (a handful of hashes), and nothing here samples
// a texture, so a stage pays only for what it calls.
//
// The reference for the wave field is the WebGPU water simulation (jeantimex/webgpu-water) and the
// Gerstner-wave look real shaders use: a sum of directional waves whose lengths, directions and
// speeds all differ, so crests drift instead of locking into a repeating grid. Horizon's material
// stage is per fragment on an already-built block face, so the field shades the surface (its normal)
// rather than displacing geometry; the geometry is vanilla's water block.
//
// The rings only read `frame.time`, `frame.rain`, `frame.camera_position` and `frame.eye_in`, all of
// which every build of the game gives a pack, so the pack loads everywhere.

override water: bool = true;
override water_waves: f32 = 0.5;
override water_specular: f32 = 0.6;
override water_reflect: f32 = 0.5;
override water_caustics: f32 = 0.5;
override water_ripples: f32 = 0.6;

// A water surface normal from four travelling waves: a long swell, two crossing chop trains and one
// fine ripple. Their directions, lengths and speeds all differ, so the crests drift; the gradient is
// analytic, so this is a handful of cosines and no texture read. `amplitude` 0 is flat water.
fn wave_normal(p: vec2<f32>, amplitude: f32, scale: f32, speed: f32) -> vec3<f32> {
    let t = frame.time * speed;
    let k1 = vec2<f32>(0.62, 0.78) * scale * 0.7;
    let k2 = vec2<f32>(-0.70, 0.71) * scale * 1.6;
    let k3 = vec2<f32>(0.28, -0.96) * scale * 2.9;
    let k4 = vec2<f32>(-0.45, -0.89) * scale * 4.7;
    let p1 = dot(k1, p) + t;
    let p2 = dot(k2, p) - t * 1.23;
    let p3 = dot(k3, p) + t * 1.7;
    let p4 = dot(k4, p) - t * 2.3;
    let dx = k1.x * cos(p1) + k2.x * cos(p2) + k3.x * cos(p3) * 0.7 + k4.x * cos(p4) * 0.45;
    let dz = k1.y * cos(p1) + k2.y * cos(p2) + k3.y * cos(p3) * 0.7 + k4.y * cos(p4) * 0.45;
    return normalize(vec3<f32>(-dx * amplitude, 1.0, -dz * amplitude));
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

// A GGX micro-facet specular term: a tighter, more believable sun or moon highlight than a plain
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

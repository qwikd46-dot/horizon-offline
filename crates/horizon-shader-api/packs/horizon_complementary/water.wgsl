// The water surface: a travelling-wave field, the caustics the sun casts through it, and the ripples
// a player or mob leaves behind. Shared by the pack, so the material stage calls it and the sky and
// post stages simply do not. Every wave is analytic (a few cosines), the ripples read the per-frame
// `frame.water_disturb` list, and nothing here samples a texture, so a stage pays only for what it
// calls.
//
// The reference for the wave field is the WebGPU water simulation (jeantimex/webgpu-water) and the
// Gerstner-wave look real shaders use: a sum of directional waves whose lengths, directions and
// speeds all differ, so crests drift instead of locking into a repeating grid. Horizon's material
// stage is per fragment on an already-built block face, so the field shades the surface (its normal)
// rather than displacing geometry; the geometry is vanilla's water block.

override water: bool = true;
override water_waves: f32 = 0.5;
override water_specular: f32 = 0.6;
override water_reflect: f32 = 0.5;
override water_caustics: f32 = 0.5;
override water_disturb_strength: f32 = 0.6;

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

// The normal the ripples a player or mob left add to the surface at `p` (world xz). Each source in
// `frame.water_disturb` is a ring: sin(pi * r/R) is zero at its centre and its rim and strongest
// between, and its gradient tilts the normal along the ring, so the crest pushes outward and a
// trough trails behind. `view_dist` fades the rings out with distance so far water stays calm.
fn water_ripples(p: vec2<f32>, view_dist: f32) -> vec3<f32> {
    let fade = 1.0 - smoothstep(24.0, 56.0, view_dist);
    if fade <= 0.0 {
        return vec3<f32>(0.0, 0.0, 0.0);
    }
    var dx = 0.0;
    var dz = 0.0;
    for (var i = 0u; i < 16u; i = i + 1u) {
        let s = frame.water_disturb[i];
        let radius = s.z;
        // Unused slots are all zero: no radius, no ripple.
        if radius <= 0.0 {
            continue;
        }
        let d = p - s.xy;
        let r = length(d);
        if r >= radius {
            continue;
        }
        let x = r / radius;
        // d(sin(pi*x))/dr = pi/R * cos(pi*x): the slope of the ring.
        let slope = 3.14159265 / radius * cos(x * 3.14159265);
        let dir = select(vec2<f32>(1.0, 0.0), d / r, r > 1e-4);
        let k = slope * s.w * water_disturb_strength * fade;
        dx += dir.x * k;
        dz += dir.y * k;
    }
    return vec3<f32>(-dx, 0.0, -dz);
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

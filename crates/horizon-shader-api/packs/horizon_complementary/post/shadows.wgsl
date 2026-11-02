// Screen-space ambient occlusion and contact shadows. The engine has neither, so this adds the
// dark seam where a wall meets the ground and the soft shade under objects, from the depth already
// in the picture: a few taps, no extra geometry pass. The first post pass, so bloom and the grade
// see the shaded picture.
override shadows: bool = true;
override ao_strength: f32 = 0.55;
override ao_radius: f32 = 1.3;
override performance_mode: bool = false;

fn post(input: PostInput) -> vec4<f32> {
    // The sky has no surface to shade.
    if !shadows || input.depth >= 1.0 {
        return input.color;
    }
    let p = view_position(input.uv, input.depth);
    let dist_cam = max(length(p), 0.5);
    // A world-space radius, as a fraction of the screen, shrinks with distance from the eye.
    let uv_radius = ao_radius / dist_cam * 0.4;
    let taps = select(10, 5, performance_mode);
    let golden = 2.3999632;
    var occ = 0.0;
    for (var i = 0; i < taps; i++) {
        let f = (f32(i) + 0.5) / f32(taps);
        let a = f32(i) * golden;
        let suv = input.uv + vec2<f32>(cos(a), sin(a)) * sqrt(f) * uv_radius;
        let sd = depth_at(suv);
        // A nearer surface than this pixel (reversed depth: larger is nearer) shades it.
        if sd > input.depth {
            let d = length(view_position(suv, sd) - p);
            occ += max(0.0, 1.0 - d / ao_radius);
        }
    }
    let ao = 1.0 - (occ / f32(taps)) * ao_strength;
    return vec4<f32>(input.color.rgb * clamp(ao, 0.0, 1.0), input.color.a);
}

// Screen-space ambient occlusion and contact shadows. The engine has neither, so this adds the dark
// seam where a wall meets the ground and the soft shade under objects, from the depth already in the
// picture: a few taps, no extra geometry pass. The first post pass, so bloom and the grade see the
// shaded picture. The tap count follows the "Night quality" preset (capped by the Shadows quality
// setting), and the far half of the view (where the occlusion is invisible) is skipped before any tap.
//
// The taps are taken at a *screen* radius, not a world one: a world radius grows without bound as the
// surface comes close, so the pattern swam across flat faces and made them look like they were
// moving. A screen radius (clamped, so it never smears) plus a depth bias keeps the shade pinned to
// the geometry. The occlusion is deliberately gentle: a strong, wide AO darkens the whole scene with
// distance and reads as the blocks shifting, which is worse than no AO at all.
override shadows: bool = true;
override ao_strength: f32 = 0.3;
override ao_radius: f32 = 1.0;
override ao_quality: i32 = 2;
override night_quality: u32 = 1;
override performance_mode: bool = false;

fn post(input: PostInput) -> vec4<f32> {
    // The sky has no surface to shade. Depth is reversed: the sky and the far plane are 0.
    if !shadows || input.depth <= 0.0 {
        return input.color;
    }
    let p = view_position(input.uv, input.depth);
    let dist_cam = max(length(p), 0.5);
    // Past half the render distance the occlusion is sub-pixel and only costs taps.
    if dist_cam > frame.render_distance * 0.5 {
        return input.color;
    }
    var taps = 10;
    if ao_quality <= 0 {
        taps = 4;
    } else if ao_quality == 1 {
        taps = 6;
    } else if ao_quality >= 3 {
        taps = 16;
    }
    // The Night quality preset caps the taps.
    var cap = 4;
    if night_quality >= 1u {
        cap = 6;
    }
    if night_quality >= 2u {
        cap = 10;
    }
    if night_quality >= 3u {
        cap = 16;
    }
    taps = min(taps, cap);
    if performance_mode {
        taps = 4;
    }
    // A screen-space radius that shrinks with distance but is clamped to a couple of pixels: close to
    // the eye it stays small (so the pattern does not smear), far away it stays a pixel or two wide.
    let texel = 1.0 / max(frame.resolution.y, 1.0);
    let uv_radius = clamp(ao_radius / dist_cam * 0.35, texel * 1.5, texel * 9.0);
    let golden = 2.3999632;
    // A depth bias in the same reversed units, so a tap on a nearly coplanar surface does not count.
    let bias = 0.02 / (1.0 + dist_cam * 0.05);
    var occ = 0.0;
    for (var i = 0; i < taps; i++) {
        let f = (f32(i) + 0.5) / f32(taps);
        let a = f32(i) * golden;
        let suv = input.uv + vec2<f32>(cos(a), sin(a)) * sqrt(f) * uv_radius;
        let sd = depth_at(suv);
        // A nearer surface than this pixel (reversed depth: larger is nearer) shades it, once it is
        // past the bias.
        if sd > input.depth + bias {
            let d = length(view_position(suv, sd) - p);
            occ += max(0.0, 1.0 - d / ao_radius);
        }
    }
    let ao = 1.0 - (occ / f32(taps)) * ao_strength;
    return vec4<f32>(input.color.rgb * clamp(ao, 0.0, 1.0), input.color.a);
}

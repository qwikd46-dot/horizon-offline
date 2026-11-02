// A soft bloom around the brightest things: the sun, the moon, lava, torches at night, the glint on
// water. Taps are spread on a golden-angle spiral so a few of them look like a large, smooth disc,
// and every offset scales with the picture's height, so it looks the same at any resolution. The tap
// count follows the "Night quality" preset (capped by the Bloom quality setting): bloom is the
// heaviest pack pass, so it is the first to size to the GPU.
override bloom: bool = true;
override bloom_strength: f32 = 0.22;
override bloom_quality: i32 = 2;
override night_quality: u32 = 1;
override performance_mode: bool = false;

// What counts as bright enough to glow: a soft knee so the threshold never flickers.
fn bright(uv: vec2<f32>) -> vec3<f32> {
    let c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    let l = luminance(c);
    return c * smoothstep(0.6, 1.05, l);
}

fn post(input: PostInput) -> vec4<f32> {
    if !bloom || bloom_strength <= 0.0 {
        return input.color;
    }
    // By day the sky is bright everywhere: let it glow a quarter as much as the rest.
    let open = select(1.0, 0.25, input.depth == 0.0);
    // A pixel is `1/resolution` of the picture; scale the spread with the height so the bloom
    // keeps its size at 720p, 1440p and every resolution scale.
    let texel = frame.resolution.y / 720.0 / frame.resolution;
    let golden = 2.3999632;
    var tight = 10;
    var wide = 14;
    if bloom_quality <= 0 {
        tight = 8;
        wide = 0;
    } else if bloom_quality == 1 {
        tight = 10;
        wide = 8;
    } else if bloom_quality >= 3 {
        tight = 16;
        wide = 16;
    }
    // The Night quality preset caps the taps.
    var cap_tight = 8;
    var cap_wide = 0;
    if night_quality >= 1u {
        cap_tight = 10;
        cap_wide = 8;
    }
    if night_quality >= 2u {
        cap_tight = 14;
        cap_wide = 12;
    }
    if night_quality >= 3u {
        cap_tight = 16;
        cap_wide = 16;
    }
    tight = min(tight, cap_tight);
    wide = min(wide, cap_wide);
    if performance_mode {
        tight = 8;
        wide = 0;
    }
    var sum = vec3<f32>(0.0);
    var weight = 0.0;
    // Tight ring: weighted toward the centre.
    for (var i = 0; i < tight; i++) {
        let r = sqrt((f32(i) + 0.5) / f32(tight)) * 2.2;
        let a = f32(i) * golden;
        let w = 1.0 - f32(i) / f32(tight + 4);
        sum += bright(input.uv + vec2<f32>(cos(a), sin(a)) * r * texel) * w;
        weight += w;
    }
    // Wide ring: a softer halo over the tight one. Skipped when `wide` is 0.
    for (var i = 0; i < wide; i++) {
        let r = 2.6 + sqrt((f32(i) + 0.5) / f32(max(wide, 1))) * 3.4;
        let a = f32(i) * golden + 1.3;
        let w = 0.8 - f32(i) / (f32(max(wide, 1)) * 1.6);
        sum += bright(input.uv + vec2<f32>(cos(a), sin(a)) * r * texel) * w;
        weight += w;
    }
    return vec4<f32>(input.color.rgb + sum * (bloom_strength * open * 1.6 / max(weight, 1.0)), input.color.a);
}

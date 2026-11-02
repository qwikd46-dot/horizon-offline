// A soft bloom around the brightest things: the sun, lava, torches at night, the glint on
// water. Taps are spread on a golden-angle spiral so a few of them look like a large, smooth
// disc, and every offset scales with the picture's height, so it looks the same at any
// resolution. Performance mode keeps the tight ring only.
override bloom: bool = true;
override bloom_strength: f32 = 0.3;
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
    var sum = vec3<f32>(0.0);
    var weight = 0.0;
    // Tight ring: 10 taps inside 2.6 texels, weighted toward the centre.
    for (var i = 0; i < 10; i++) {
        let r = sqrt((f32(i) + 0.5) / 10.0) * 2.6;
        let a = f32(i) * golden;
        let w = 1.0 - f32(i) / 14.0;
        sum += bright(input.uv + vec2<f32>(cos(a), sin(a)) * r * texel) * w;
        weight += w;
    }
    if !performance_mode {
        // Wide ring: 14 taps out to 7 texels, a softer halo over the tight one.
        for (var i = 0; i < 14; i++) {
            let r = (3.0 + sqrt((f32(i) + 0.5) / 14.0) * 4.0);
            let a = f32(i) * golden + 1.3;
            let w = 0.8 - f32(i) / 22.0;
            sum += bright(input.uv + vec2<f32>(cos(a), sin(a)) * r * texel) * w;
            weight += w;
        }
    }
    return vec4<f32>(input.color.rgb + sum * (bloom_strength * open * 1.6 / max(weight, 1.0)), input.color.a);
}

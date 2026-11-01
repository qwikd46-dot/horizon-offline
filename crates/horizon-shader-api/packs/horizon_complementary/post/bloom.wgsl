// A soft bloom around the brightest things: the sun, lava, torches at night, the glint on
// water. Two rings of taps scaled with the picture's height, so it looks the same at any
// resolution; performance mode keeps the inner ring only.
override bloom: bool = true;
override bloom_strength: f32 = 0.3;
override performance_mode: bool = false;

// What counts as bright enough to glow.
fn bright(uv: vec2<f32>) -> vec3<f32> {
    let c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    return c * smoothstep(0.72, 1.0, luminance(c));
}

fn post(input: PostInput) -> vec4<f32> {
    if !bloom || bloom_strength <= 0.0 {
        return input.color;
    }
    // By day the sky is bright everywhere: let it glow a quarter as much as the rest.
    let open = select(1.0, 0.25, input.depth == 0.0);
    let texel = frame.resolution.y / 720.0 / frame.resolution;
    var sum = vec3<f32>(0.0);
    // Inner ring: 8 taps at 45 degrees.
    for (var i = 0; i < 8; i++) {
        let angle = f32(i) * 0.7853982;
        sum += bright(input.uv + vec2<f32>(cos(angle), sin(angle)) * 2.5 * texel);
    }
    var taps = 8.0;
    if !performance_mode {
        // Outer ring: 12 taps at 30 degrees, a wider and softer spread.
        for (var i = 0; i < 12; i++) {
            let angle = f32(i) * 0.5235988;
            sum += bright(input.uv + vec2<f32>(cos(angle), sin(angle)) * 6.5 * texel) * 0.7;
        }
        taps = 16.4;
    }
    return vec4<f32>(input.color.rgb + sum * (bloom_strength * open / taps), input.color.a);
}

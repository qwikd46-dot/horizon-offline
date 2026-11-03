// Every point of a block's surface: vanilla's lightmap, warmed for torch light, lit by the moon at
// night and the low sun at dusk, a cool sky ambient, and only a little aerial haze. Water is left
// to a water mod. Horizon applies the alpha test and its own fog
// after this. The pack cannot see a surface normal, so the moon light is hemispheric: what the sky
// reaches is what the moon lights, and the post pass adds the local shade.
override fog: bool = true;
override fog_amount: f32 = 0.1;
override night_boost: f32 = 0.16;
override moonlight: f32 = 0.55;
override sun_strength: f32 = 0.55;

fn material(input: MaterialInput) -> Surface {
    let block = input.light.x;
    let sky = input.light.y;
    let n = night();
    var lit: vec3<f32>;
    if frame.dimension == 0 {
        // Complementary's lighting, minus the shadow map the engine does not offer: the ambient
        // sky colour, the sun (by day) or moon (by night) as a direct light on what the sky
        // reaches, warm block light, and a floor so caves are never black. Computed in linear
        // light and tonemapped once.
        let lin = to_linear(input.albedo.rgb * input.tint.rgb);
        let sl = sky * sky;
        let direct = mix(sun_strength, moonlight * 1.4, n) * (1.0 - frame.rain * 0.35);
        let ambient = cr_ambient_color() * sl;
        let direct_light = cr_light_color() * sl * direct;
        let lamp = vec3<f32>(1.45, 0.88, 0.58) * pow(block, 3.0);
        let floor_light = vec3<f32>(0.025 + 0.04 * frame.brightness + 0.35 * frame.night_vision);
        lit = cr_tonemap(lin * (ambient + direct_light + lamp + floor_light) * (1.0 + night_boost * n));
    } else {
        lit = input.albedo.rgb * input.tint.rgb * input.lightmap;
    }

    // Underwater, drift everything toward the water's tint and dim with distance from the eye.
    if frame.eye_in == 1u {
        lit *= mix(vec3<f32>(0.6, 0.8, 1.0), vec3<f32>(0.78, 0.9, 1.0), smoothstep(0.0, 16.0, length(input.position)));
    }

    // Water is left to a water mod (it owns the surface, its waves and its reflections); this stage
    // only lights the block, so water keeps vanilla's albedo and lightmap.

    // Aerial haze: distant land drifts toward the fog colour, but only near the far plane so the
    // middle distance stays clear, and toward the sky colour so the horizon never goes flat.
    if fog {
        let dist = length(input.position);
        // Only the last stretch before the far plane: most real shaders keep the middle distance
        // clear, and a haze that starts early is what made the whole view look washed out.
        let start = max(frame.fog_start, frame.fog_end * 0.88);
        let haze = smoothstep(start, max(frame.fog_end, start + 1.0), dist) * fog_amount;
        let tint = mix(frame.fog_color, frame.sky_color, 0.5 * n);
        let warm = mix(tint, tint * sun_tint(), min(sun_low() * daylight(), 1.0) * 0.5);
        lit = mix(lit, warm, haze);
    }

    return Surface(vec4<f32>(max(lit, vec3<f32>(0.0)), input.albedo.a * input.tint.a));
}

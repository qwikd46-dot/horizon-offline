// Every point of a block's surface: vanilla's lightmap, warmed for torch light, lit by the moon at
// night and the low sun at dusk, a cool sky ambient, and only a little aerial haze. Water's top face
// takes Water Shader Alpha's surface: waves, the game's water mirror (the `reflection` texture) and
// the sun's or moon's glint. Horizon applies the alpha test and its own fog
// after this. The pack cannot see a surface normal, so the moon light is hemispheric: what the sky
// reaches is what the moon lights, and the post pass adds the local shade.
override fog: bool = true;
override fog_amount: f32 = 0.1;
override night_boost: f32 = 0.16;
override moonlight: f32 = 0.55;
override sun_strength: f32 = 0.55;
override water: bool = true;
override water_reflect_on: bool = true;
override water_waves: f32 = 0.5;
override water_reflect: f32 = 0.6;
override water_specular: f32 = 0.7;

// A travelling-wave normal on the water's top face, world-anchored so the pattern stays put as you
// walk. Three wave trains at different scales and speeds, summed as slopes, give the crossing swell
// Water Shader Alpha's surface has without a texture read.
fn water_normal(world_xz: vec2<f32>, t: f32, strength: f32) -> vec3<f32> {
    let dirs = array<vec2<f32>, 3>(
        vec2<f32>(0.86, 0.51), vec2<f32>(-0.42, 0.91), vec2<f32>(0.20, -0.98));
    let scales = array<f32, 3>(0.42, 0.83, 1.70);
    let speeds = array<f32, 3>(0.90, 1.30, 2.10);
    var slope = vec2<f32>(0.0);
    for (var i = 0; i < 3; i = i + 1) {
        let phase = dot(world_xz, dirs[i]) * scales[i] + t * speeds[i];
        slope += dirs[i] * cos(phase) * scales[i];
    }
    return normalize(vec3<f32>(slope.x, 0.0, slope.y) * strength + vec3<f32>(0.0, 1.0, 0.0));
}

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

    // Water's top face: Water Shader Alpha's surface. The engine's water mirror is only there while
    // `has_reflection` is 1, so without it the surface falls back to the sky's colour; the waves and
    // the glint read nothing, so they cost no texture fetch.
    let is_water = water && input.fluid == 1u && input.face == 1u && frame.dimension == 0;
    if is_water {
        let view = -normalize(input.position + vec3<f32>(0.0, 0.001, 0.0));
        let world_xz = input.position.xz + frame.camera_position.xz;
        let nrm = water_normal(world_xz, frame.time, water_waves * 0.6);
        let fres = clamp(0.02 + 0.98 * pow(1.0 - max(dot(view, nrm), 0.0), 5.0), 0.0, 1.0);

        // The mirror where the renderer draws it, else the sky the water would reflect.
        var reflected = frame.sky_color;
        if water_reflect_on && frame.has_reflection == 1u {
            reflected = textureSampleLevel(reflection, reflection_sampler, input.screen, 0.0).rgb;
        }
        var water_lit = mix(lit, reflected, fres * water_reflect);

        // The sun's or moon's glint on the waves: GGX, with the moon also giving a soft broad sheen.
        let moon = moon_up() * (1.0 - daylight());
        let sun = daylight() * (1.0 - frame.rain * 0.6);
        water_lit += specular(nrm, view, frame.sun_direction, 200.0) * sun_color() * sun * water_specular;
        water_lit += (specular(nrm, view, frame.moon_direction, 120.0) * 0.6
            + pow(max(dot(nrm, frame.moon_direction), 0.0), 8.0) * 0.18)
            * moon_color() * moon * water_specular;

        lit = water_lit;
    }

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

// Every point of a block's surface: vanilla's lightmap, warmed for torch light, lit by the moon at
// night and the low sun at dusk, and gently hazed at the horizon. Water uses a blue absorption tint,
// Fresnel sky reflection and visibly travelling surface waves. Horizon applies alpha and fog after
// this stage; its material API does not expose scene depth or geometry displacement.
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

    // Water is identified by its open-sky translucent surface. The material API does not expose a
    // block id, so keep the effect close to the camera where water occupies most of the view.
    let is_water = input.translucent && sky > 0.8 && block < 0.25 && frame.dimension == 0;
    if water && is_water {
        let dist = length(input.position);
        let view = -normalize(input.position + vec3<f32>(0.0, 0.001, 0.0));
        let near = 1.0 - smoothstep(28.0, 64.0, dist);
        let world_xz = input.position.xz + frame.camera_position.xz;
        let waves = water_waves_at(world_xz, frame.time, water_waves * near);
        let nrm = water_normal(waves);

        // Red light is absorbed faster than blue. The clarity control shortens the optical path,
        // while the small blue body term keeps water recognizable under a pale or dark sky.
        let optical_path = 1.6 / max(water_clarity, 0.1);
        let transmission = exp(-vec3<f32>(0.24, 0.075, 0.03) * optical_path);
        let sky = max(frame.sky_color, vec3<f32>(0.015));
        let body = mix(sky, vec3<f32>(0.10, 0.24, 0.40), 0.32);
        let deep = vec3<f32>(0.012, 0.045, 0.105);
        var water_lit = body * transmission + deep * (vec3<f32>(1.0) - transmission);
        // A low-contrast moving body tone makes the waves visible from above, not only in highlights.
        water_lit *= 1.0 + waves.height * 0.18;

        // Water reflects little head-on and more at a grazing angle. Only the sky is available to
        // reflect; scene-colour refraction and depth-based absorption need renderer API support.
        let fres = 0.02 + 0.98 * pow(1.0 - max(dot(view, nrm), 0.0), 5.0);
        water_lit = mix(water_lit, frame.sky_color, fres * water_reflect * near);

        let reflected = reflect(-view, nrm);
        let sun_glint = pow(max(dot(reflected, frame.sun_direction), 0.0), 52.0);
        let moon_glint = pow(max(dot(reflected, frame.moon_direction), 0.0), 42.0);
        water_lit += sun_color() * sun_glint * daylight() * (1.0 - frame.rain * 0.8)
            * water_specular * near * 0.18;
        water_lit += moon_color() * moon_glint * moon_up() * n * water_specular * near * 0.08;
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

    // Keep enough opacity for the water's blue body colour to read against the world underneath.
    var alpha = input.albedo.a * input.tint.a;
    if water && is_water {
        let near = 1.0 - smoothstep(28.0, 64.0, length(input.position));
        alpha = mix(alpha, 0.74, near);
    }
    return Surface(vec4<f32>(max(lit, vec3<f32>(0.0)), alpha));
}

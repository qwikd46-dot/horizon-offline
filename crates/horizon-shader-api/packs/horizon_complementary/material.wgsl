// Every point of a block's surface: vanilla's lightmap, warmed for torch light, lit by the moon at
// night and the low sun at dusk, a cool sky ambient, real waves with a moon glint and a sky
// reflection on water, and only a little aerial haze. Horizon applies the alpha test and its own fog
// after this. The pack cannot see a surface normal, so the moon light is hemispheric: what the sky
// reaches is what the moon lights, and the post pass adds the local shade.
override fog: bool = true;
override fog_amount: f32 = 0.22;
override night_boost: f32 = 0.16;
override moonlight: f32 = 0.55;
override water: bool = true;
override water_waves: f32 = 0.5;
override water_specular: f32 = 0.9;
override water_reflect: f32 = 0.5;

fn material(input: MaterialInput) -> Surface {
    let block = input.light.x;
    let sky = input.light.y;
    var color = input.albedo.rgb * input.tint.rgb;

    // Torch light is warmer than daylight: pull the lightmap toward amber as block light rises.
    let lamp = smoothstep(0.0, 0.65, block);
    let warm = mix(vec3<f32>(1.16, 1.0, 0.82), vec3<f32>(1.22, 0.94, 0.68), lamp * 0.5);
    let lightmap = mix(input.lightmap, input.lightmap * warm, lamp) * (1.0 + lamp * 0.06);
    var lit = color * lightmap;

    // How much sky reaches this surface, and how dark it is out: what the night light works on.
    let open = sky;
    let n = night();
    let twilight = twilight();

    // The moon: a cool directional light, phase- and height-scaled, on what the sky reaches. This
    // is what makes canopy, trunks and hills readable at night instead of a near-black green.
    lit += color * moon_color() * (moonlight * moon_up() * n * open);

    // The night sky's ambient, stronger from above, with a faint ground bounce, so shadows are deep
    // blue rather than black. Only where the sky reaches, and never on top of torch light.
    lit += color * night_ambient(open) * (n * open * (1.0 - lamp) * 0.7);

    // A last, gentle artistic lift in the open at night, in a cool tone.
    lit += color * night_boost * open * n * vec3<f32>(0.32, 0.44, 0.82) * 0.5;

    // The low sun at dusk and dawn: a warm, weak directional light on what the sky reaches, so the
    // land is not black while the sky is golden.
    lit += color * sun_color() * (twilight * open * (1.0 - n) * 0.16);

    // Underwater, drift everything toward the water's tint and dim with distance from the eye.
    if frame.eye_in == 1u {
        lit *= mix(vec3<f32>(0.6, 0.8, 1.0), vec3<f32>(0.78, 0.9, 1.0), smoothstep(0.0, 16.0, length(input.position)));
    }

    // Water and ice: the flat top face of a translucent block in the open sky. A real wave normal
    // gives a sun or moon highlight and a sky reflection that grows at grazing angles.
    let is_water = input.translucent && sky > 0.8 && block < 0.25 && frame.dimension == 0;
    if water && is_water {
        let nrm = wave_normal(input.position.xz + vec2<f32>(frame.camera_position.x, frame.camera_position.z), water_waves, 0.35, 0.55);
        let view = -normalize(input.position + vec3<f32>(0.0, 0.001, 0.0));
        let sun_high = max(frame.sun_direction.y, 0.0);
        let clear = 1.0 - frame.rain;

        // The water body: darker and less saturated than the sky, tinted by the sky's own colour.
        // Shallow reads teal, deep near-black navy, so it never glows on its own.
        let shallow = vec3<f32>(0.06, 0.13, 0.16);
        let deep = vec3<f32>(0.02, 0.04, 0.09);
        let body = mix(deep, shallow, clamp(open * 0.6 + 0.4, 0.0, 1.0));
        let tinted = mix(body, body * (frame.sky_color * 1.4 + 0.15), 0.45);
        var water_lit = mix(lit * 0.4, tinted, 0.75);

        // Fresnel: more reflective at grazing angles, darker looking straight down.
        let fres = fresnel(view, nrm, 5.0);
        let reflected_sky = mix(frame.sky_color, frame.sky_color * 1.25 + vec3<f32>(0.04), fres);
        // The moon on the water: a broad soft glint that breaks up with the wave normal.
        let to_moon = max(dot(nrm, frame.moon_direction), 0.0);
        let moon_glint = (specular(nrm, view, frame.moon_direction, 220.0) + pow(to_moon, 6.0) * 0.35)
            * moon_color() * moon_up() * n * clear * water_specular;
        let reflected = (reflected_sky * (1.0 - n) + moon_color() * 0.25 * n) * water_reflect + moon_glint;
        water_lit = mix(water_lit, water_lit * 0.7 + reflected, clamp(fres * 0.9 + 0.12, 0.0, 1.0));

        // The sun's own glint by day.
        water_lit += specular(nrm, view, frame.sun_direction, 140.0)
            * sun_color() * daylight() * clear * water_specular * sun_high;

        // A little foam/shore sparkle from the waves, brightest in moonlight.
        water_lit += vec3<f32>(0.5, 0.6, 0.75) * pow(max(to_moon, 0.0), 2.0) * moon_up() * n * 0.06;

        lit = water_lit;
    }

    // Aerial haze: distant land drifts toward the fog colour, but only near the far plane so the
    // middle distance stays clear, and toward the sky colour so the horizon never goes flat.
    if fog {
        let dist = length(input.position);
        let start = max(frame.fog_start, frame.fog_end * 0.62);
        let haze = smoothstep(start, max(frame.fog_end, start + 1.0), dist) * fog_amount;
        let tint = mix(frame.fog_color, frame.sky_color, 0.5 * n);
        let warm = mix(tint, tint * sun_tint(), min(sun_low() * daylight(), 1.0) * 0.5);
        lit = mix(lit, warm, haze);
    }

    return Surface(vec4<f32>(max(lit, vec3<f32>(0.0)), input.albedo.a * input.tint.a));
}

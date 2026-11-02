// Every point of a block's surface: vanilla's lightmap, warmed for torch light, lit by the moon at
// night and the low sun at dusk, a cool sky ambient, real waves with a moon glint and a sky
// reflection on water, and only a little aerial haze. Horizon applies the alpha test and its own fog
// after this. The pack cannot see a surface normal, so the moon light is hemispheric: what the sky
// reaches is what the moon lights, and the post pass adds the local shade.
override fog: bool = true;
override fog_amount: f32 = 0.1;
override night_boost: f32 = 0.16;
override moonlight: f32 = 0.55;

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

    // Water and ice: the flat top face of a translucent block in the open sky. Waves only tilt the
    // normal (the albedo keeps vanilla's water texture), and the wave, the reflection, the glint and
    // the ripples all fade out with distance, so far water is a calm flat sheet instead of a
    // shimmering pattern.
    let is_water = input.translucent && sky > 0.8 && block < 0.25 && frame.dimension == 0;
    if water && is_water {
        let dist = length(input.position);
        let view = -normalize(input.position + vec3<f32>(0.0, 0.001, 0.0));
        // Wave and ripple detail is only worth its cost up close; past ~64 blocks the surface is flat.
        let near = 1.0 - smoothstep(28.0, 64.0, dist);
        var nrm = wave_normal(input.position.xz, water_waves * near * 0.7, 0.32, 0.5);
        nrm = normalize(nrm + water_ripples(input.position.xz, dist));
        let sun_high = max(frame.sun_direction.y, 0.0);
        let clear = 1.0 - frame.rain;

        var water_lit = lit * 0.85;

        // Fresnel at water's index: about 2% facing the surface, near total at a grazing angle. This
        // is what makes water read as water instead of a bright mirror.
        let f0 = 0.02;
        let fres = clamp(f0 + (1.0 - f0) * pow(1.0 - max(dot(view, nrm), 0.0), 5.0), 0.0, 1.0);
        let reflected_sky = mix(frame.sky_color, frame.sky_color * 1.15, fres);

        // The moon on the water: a GGX glint plus a soft broad sheen, broken up by the wave normal,
        // dimmed at range.
        let to_moon = max(dot(nrm, frame.moon_direction), 0.0);
        let moon_glint = (ggx_specular(nrm, view, frame.moon_direction, 0.12) * 0.5 + pow(to_moon, 8.0) * 0.18)
            * moon_color() * moon_up() * n * clear * water_specular * near;
        let reflected = (reflected_sky * (1.0 - n) + moon_color() * 0.22 * n) * water_reflect * near + moon_glint;
        water_lit = mix(water_lit, water_lit * 0.35 + reflected, fres);

        // The sun's own glint by day, a touch tighter than the moon's, also faded at range.
        water_lit += ggx_specular(nrm, view, frame.sun_direction, 0.09)
            * sun_color() * daylight() * clear * water_specular * sun_high * near * 0.8;

        // Caustics: the sun's web shimmering on the water, only in daylight and only up close.
        water_lit += sun_color() * (caustic_pattern(input.position.xz * 1.6, frame.time) * water_caustics
            * daylight() * clear * sun_high * near * 0.12);

        // A faint shore sparkle only, and only up close.
        water_lit += vec3<f32>(0.4, 0.5, 0.65) * pow(to_moon, 3.0) * moon_up() * n * 0.025 * near;

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

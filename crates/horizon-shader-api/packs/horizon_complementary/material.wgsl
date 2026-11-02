// Every point of a block's surface: vanilla's lightmap, warmed for torch light, a cool lift in the
// open at night, real waves with a sun highlight and a sky reflection on water, and only a little
// aerial haze. Horizon applies the alpha test and its own fog after this.
override fog: bool = true;
override fog_amount: f32 = 0.35;
override night_boost: f32 = 0.18;
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

    // Night brightness: lift what the sky barely lights, in a cool tone, only in the open.
    let open = (1.0 - sky) * (1.0 - daylight());
    lit += color * night_boost * open * vec3<f32>(0.32, 0.44, 0.82) * 0.5;

    // Underwater, drift everything toward the water's tint and dim with distance from the eye.
    if frame.eye_in == 1u {
        lit *= mix(vec3<f32>(0.6, 0.8, 1.0), vec3<f32>(0.78, 0.9, 1.0), smoothstep(0.0, 16.0, length(input.position)));
    }

    // Water and ice: the flat top face of a translucent block in the open sky. A real wave normal
    // gives a moving sun highlight and a sky reflection that grows at grazing angles.
    let is_water = input.translucent && sky > 0.8 && block < 0.25 && frame.dimension == 0;
    if water && is_water {
        let n = wave_normal(input.position.xz + vec2<f32>(frame.camera_position.x, frame.camera_position.z), water_waves, 0.35, 0.55);
        let view = -normalize(input.position + vec3<f32>(0.0, 0.001, 0.0));
        let sun_high = max(frame.sun_direction.y, 0.0);
        let spec = specular(n, view, frame.sun_direction, 140.0)
            * sun_color() * daylight() * (1.0 - frame.rain) * water_specular * sun_high;
        let fres = fresnel(view, n, 5.0);
        // The reflected sky, brighter toward the horizon where vanilla's sky is.
        let reflected = mix(frame.sky_color, frame.sky_color * 1.25 + vec3<f32>(0.04), fres) * water_reflect;
        lit = mix(lit, lit * 0.72 + reflected, clamp(fres * 0.9 + 0.15, 0.0, 1.0));
        lit += spec;
    }

    // Aerial haze: distant land drifts toward the fog colour, but only near the far plane so the
    // middle distance stays clear.
    if fog {
        let dist = length(input.position);
        let start = max(frame.fog_start, frame.fog_end * 0.55);
        let haze = smoothstep(start, max(frame.fog_end, start + 1.0), dist) * fog_amount;
        let tint = mix(frame.fog_color, frame.fog_color * sun_tint(), min(sun_low() * daylight(), 1.0) * 0.5);
        lit = mix(lit, tint, haze);
    }

    return Surface(vec4<f32>(max(lit, vec3<f32>(0.0)), input.albedo.a * input.tint.a));
}

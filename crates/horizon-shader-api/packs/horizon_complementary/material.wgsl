// Every point of a block's surface: vanilla's lightmap, warmed for torch light, a cool lift in
// the open at night, a sun glint on water and ice, and aerial haze toward vanilla's fog colour.
// Horizon applies the alpha test and its own fog after this.
override fog: bool = true;
override night_boost: f32 = 0.18;

fn material(input: MaterialInput) -> Surface {
    let block = input.light.x;
    let sky = input.light.y;
    var color = input.albedo.rgb * input.tint.rgb;

    // Torch light is warmer than daylight: pull the lightmap toward amber as block light rises,
    // and give a lit face a little more punch so interiors read as cosy rather than muddy.
    let lamp = smoothstep(0.0, 0.65, block);
    let warm = mix(vec3<f32>(1.16, 1.0, 0.82), vec3<f32>(1.22, 0.94, 0.68), lamp * 0.5);
    let lightmap = mix(input.lightmap, input.lightmap * warm, lamp) * (1.0 + lamp * 0.06);
    var lit = color * lightmap;

    // Night brightness: lift what the sky barely lights, in a cool tone, so caves keep their
    // shadows and only the open night gets more readable. It eases out as the sky light rises.
    let open = (1.0 - sky) * (1.0 - daylight());
    lit += color * night_boost * open * vec3<f32>(0.32, 0.44, 0.82) * 0.5;

    // Underwater, drift everything toward the water's own tint and dim with depth below the eye.
    if frame.eye_in == 1u {
        lit *= mix(vec3<f32>(0.62, 0.82, 1.0), vec3<f32>(0.78, 0.9, 1.0), smoothstep(0.0, 16.0, length(input.position)));
    }

    // A sun glint on water and ice: their faces are flat, so up is the normal to reflect over.
    // It fades with the view's angle to the water, like a real specular highlight.
    if input.translucent {
        let view = -input.position * (1.0 / max(length(input.position), 0.001));
        let reflect_dir = reflect(-frame.sun_direction, vec3<f32>(0.0, 1.0, 0.0));
        let glint = pow(max(dot(reflect_dir, view), 0.0), 64.0);
        lit += vec3<f32>(1.0, 0.93, 0.76) * glint * daylight() * (1.0 - frame.rain) * 0.75;
        // A little of the sky's colour on the water's grazing angles keeps it from looking flat.
        let fresnel = pow(1.0 - max(view.y, 0.0), 5.0);
        lit = mix(lit, mix(lit, frame.sky_color, 0.35), fresnel * 0.5);
    }

    // Aerial haze: distant land drifts toward the fog's own colour, a touch ahead of vanilla's
    // fog so the horizon reads softer.
    if fog {
        let dist = length(input.position);
        let haze = smoothstep(frame.fog_start, max(frame.fog_end, frame.fog_start + 1.0), dist);
        let tint = mix(frame.fog_color, frame.fog_color * sun_tint(), min(sun_low() * daylight(), 1.0) * 0.5);
        lit = mix(lit, tint, haze * 0.42);
    }

    return Surface(vec4<f32>(max(lit, vec3<f32>(0.0)), input.albedo.a * input.tint.a));
}

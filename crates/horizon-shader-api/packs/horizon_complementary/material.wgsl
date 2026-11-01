// Every point of a block's surface: vanilla's lightmap, warmed up for torch light, lifted a
// little at night, a sun glint on water, and aerial haze toward vanilla's fog colour. Horizon
// applies the alpha test and its own fog after this.
override fog: bool = true;
override night_boost: f32 = 0.18;

fn material(input: MaterialInput) -> Surface {
    let block = input.light.x;
    let sky = input.light.y;
    var color = input.albedo.rgb * input.tint.rgb;

    // Torch light is warmer than daylight: pull the lightmap toward amber as block light rises.
    let lamp = smoothstep(0.0, 0.6, block);
    let lightmap = mix(input.lightmap, input.lightmap * vec3<f32>(1.14, 1.0, 0.84), lamp);
    var lit = color * lightmap;

    // Night brightness: lift what the sky barely lights, in a cool tone, so caves keep their
    // shadows and only the open night gets a little more readable.
    let lift = night_boost * (1.0 - sky) * (1.0 - daylight()) * 0.45;
    lit += color * lift * vec3<f32>(0.35, 0.45, 0.8);

    // Underwater, drift everything toward the water's own tint.
    if frame.eye_in == 1u {
        lit *= vec3<f32>(0.78, 0.9, 1.0);
    }

    // A sun glint on water and ice: its faces are flat, so up is the normal to reflect over.
    if input.translucent {
        let view = -input.position * (1.0 / max(length(input.position), 0.001));
        let glint = pow(max(dot(reflect(-frame.sun_direction, vec3<f32>(0.0, 1.0, 0.0)), view), 0.0), 48.0);
        lit += vec3<f32>(1.0, 0.92, 0.74) * glint * daylight() * (1.0 - frame.rain) * 0.6;
    }

    if fog {
        let haze = smoothstep(frame.fog_start, max(frame.fog_end, frame.fog_start + 1.0), length(input.position));
        lit = mix(lit, frame.fog_color, haze * 0.4);
    }

    return Surface(vec4<f32>(max(lit, vec3<f32>(0.0)), input.albedo.a * input.tint.a));
}

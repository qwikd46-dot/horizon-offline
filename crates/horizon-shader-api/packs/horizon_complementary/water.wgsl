// Analytic travelling waves for the material stage. They animate the shading on
// Horizon's existing water mesh; the shader API does not expose vertex displacement.

override water: bool = true;
override water_waves: f32 = 0.8;
override water_specular: f32 = 0.4;
override water_reflect: f32 = 0.3;
override water_clarity: f32 = 1.1;

struct WaterWaves {
    height: f32,
    slope: vec2<f32>,
}

fn water_wave_component(
    waves: ptr<function, WaterWaves>,
    position: vec2<f32>,
    direction: vec2<f32>,
    frequency: f32,
    amplitude: f32,
    speed: f32,
    phase_offset: f32,
    time: f32,
) {
    let phase = dot(position, direction) * frequency - time * speed + phase_offset;
    (*waves).height += amplitude * sin(phase);
    (*waves).slope += direction * (amplitude * frequency * cos(phase));
}

fn water_waves_at(position: vec2<f32>, time: f32, strength: f32) -> WaterWaves {
    var waves = WaterWaves(0.0, vec2<f32>(0.0));
    water_wave_component(&waves, position, normalize(vec2<f32>(0.96, 0.28)), 0.38, 0.20, 0.72, 0.4, time);
    water_wave_component(&waves, position, normalize(vec2<f32>(-0.38, 0.92)), 0.62, 0.12, 0.96, 2.1, time);
    water_wave_component(&waves, position, normalize(vec2<f32>(0.75, -0.66)), 1.12, 0.05, 1.31, 4.3, time);
    water_wave_component(&waves, position, normalize(vec2<f32>(-0.82, -0.57)), 2.05, 0.012, 1.68, 1.7, time);
    waves.height *= strength;
    waves.slope *= strength;
    return waves;
}

fn water_normal(waves: WaterWaves) -> vec3<f32> {
    return normalize(vec3<f32>(-waves.slope.x, 1.0, -waves.slope.y));
}

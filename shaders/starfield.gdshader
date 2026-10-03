shader_type canvas_item;

// Full-screen background: dark sky, a faint nebula haze, and three layers of stars that drift at
// different speeds as the camera moves (parallax).

// Camera position scaled to pixels. Set by the Starfield script.
uniform vec2 offset = vec2(0.0);
uniform vec2 screen_size = vec2(1600.0, 900.0);
uniform vec3 sky_color : source_color = vec3(0.012, 0.016, 0.035);
uniform vec3 nebula_color_a : source_color = vec3(0.17, 0.08, 0.3);
uniform vec3 nebula_color_b : source_color = vec3(0.04, 0.14, 0.28);
uniform float nebula_strength = 0.3;
uniform float star_brightness = 0.8;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * value_noise(p);
		p = p * 2.07 + vec2(3.1, 7.7);
		amplitude *= 0.5;
	}
	return value;
}

// One star per cell at most, at a random spot away from the cell edges.
float stars(vec2 px, float cell_size, float density, float star_size) {
	vec2 cell = floor(px / cell_size);
	if (hash12(cell) > density) {
		return 0.0;
	}
	vec2 center = (0.15 + 0.7 * hash22(cell)) * cell_size;
	float brightness = hash12(cell + 17.0);
	float twinkle = 0.85 + 0.15 * sin(TIME * (0.7 + brightness * 2.0) + brightness * 40.0);
	float d = length(px - cell * cell_size - center);
	return smoothstep(star_size, 0.0, d) * (0.3 + 0.7 * brightness) * twinkle;
}

void fragment() {
	vec2 px = UV * screen_size;
	vec3 color = sky_color;

	vec2 nebula_point = (px + offset * 0.1) * 0.0011;
	float haze = smoothstep(0.42, 0.85, fbm(nebula_point));
	color += mix(nebula_color_a, nebula_color_b, fbm(nebula_point * 1.6 + 5.0)) * haze * nebula_strength;

	color += vec3(0.7, 0.78, 1.0) * stars(px + offset * 0.25, 60.0, 0.35, 1.1) * 0.45 * star_brightness;
	color += vec3(1.0, 0.95, 0.88) * stars(px + offset * 0.5, 105.0, 0.3, 1.5) * 0.7 * star_brightness;
	color += vec3(0.9, 0.95, 1.0) * stars(px + offset, 180.0, 0.25, 2.0) * star_brightness;

	COLOR = vec4(color, 1.0);
}

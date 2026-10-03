shader_type canvas_item;

// Draws a lit, slowly rotating sphere with procedural terrain, optional oceans, ice caps, craters,
// clouds and an atmosphere glow. Drawn on a square whose UVs span the body plus its atmosphere.

uniform vec4 ocean_color : source_color = vec4(0.08, 0.22, 0.45, 1.0);
uniform vec4 land_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 highland_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);
// Terrain height above which there is land. 0 means no ocean.
uniform float land_level = 0.0;
uniform float noise_scale = 2.5;
uniform vec4 cap_color : source_color = vec4(0.93, 0.96, 1.0, 1.0);
// |latitude| (0 at equator, 1 at the poles) where ice caps start. Above 1 means no caps.
uniform float cap_latitude = 2.0;
uniform float crater_amount = 0.0;
uniform float cloud_amount = 0.0;
uniform vec4 atmosphere_color : source_color = vec4(0.45, 0.7, 1.0, 0.0);
// Body radius divided by the drawn radius (body + atmosphere). Set by CelestialBody.
uniform float body_fraction = 1.0;
// Points toward the sun, in screen space (y down).
uniform vec2 light_direction = vec2(-0.85, -0.35);
uniform float night_brightness = 0.05;
// Rotation angle in radians. Set by CelestialBody from the simulation clock.
uniform float spin = 0.0;
uniform float seed = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amplitude *= 0.5;
	}
	return value;
}

// Brightness multiplier from craters: each cell may hold one crater of random size, with a dark
// bowl and a faint rim.
float craters(vec3 p, float density) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float shade = 1.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 cell = i + vec3(float(x), float(y), float(z));
				if (hash(cell + 51.3) > density) {
					continue;
				}
				vec3 center = vec3(float(x), float(y), float(z)) + vec3(hash(cell), hash(cell + 13.1), hash(cell + 27.7));
				float size = mix(0.18, 0.42, hash(cell + 7.9));
				float d = length(center - f) / size;
				float bowl = mix(0.62, 1.0, smoothstep(0.0, 0.95, d));
				float rim = 1.0 + 0.07 * smoothstep(0.8, 0.97, d) * (1.0 - smoothstep(0.97, 1.2, d));
				shade *= d < 1.2 ? bowl * rim : 1.0;
			}
		}
	}
	return shade;
}

vec3 rotate_y(vec3 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.5;
	vec3 light = normalize(vec3(light_direction, 0.65));
	vec4 result = vec4(0.0);

	if (atmosphere_color.a > 0.0 && body_fraction < 1.0) {
		float t = clamp((r - body_fraction) / (1.0 - body_fraction), 0.0, 1.0);
		float facing_sun = clamp(dot(normalize(vec3(p, 0.0001)), light) * 0.6 + 0.45, 0.0, 1.0);
		float alpha = atmosphere_color.a * pow(1.0 - t, 2.0) * facing_sun * (1.0 - smoothstep(1.0 - aa, 1.0, r));
		result = vec4(atmosphere_color.rgb, alpha);
	}

	float rs = r / body_fraction;
	if (rs < 1.0 + aa / body_fraction) {
		float z = sqrt(max(0.0, 1.0 - rs * rs));
		vec3 normal = vec3(p / body_fraction, z);
		vec3 surface_point = rotate_y(normal, spin);
		vec3 terrain_point = surface_point * noise_scale + seed;
		float height = fbm(terrain_point);

		vec3 color = mix(land_color.rgb, highland_color.rgb, smoothstep(0.35, 0.65, height));
		if (land_level > 0.0) {
			vec3 land = mix(land_color.rgb, highland_color.rgb, smoothstep(land_level + 0.08, land_level + 0.25, height));
			color = mix(ocean_color.rgb, land, smoothstep(land_level, land_level + 0.02, height));
		}
		color = mix(color, cap_color.rgb, smoothstep(cap_latitude, cap_latitude + 0.08, abs(surface_point.y) + (height - 0.5) * 0.35));

		if (crater_amount > 0.0) {
			float shade = craters(terrain_point * 2.0, 0.55) * craters(terrain_point * 5.5 + 3.3, 0.35);
			color *= mix(1.0, shade, crater_amount);
		}

		if (cloud_amount > 0.0) {
			vec3 cloud_point = rotate_y(normal, spin * 1.35) * 3.0 + seed + 40.0;
			color = mix(color, vec3(1.0), smoothstep(0.55, 0.78, fbm(cloud_point)) * cloud_amount);
		}

		float sunlight = smoothstep(-0.08, 0.5, dot(normal, light));
		vec3 lit = color * (night_brightness + (1.0 - night_brightness) * sunlight);
		if (atmosphere_color.a > 0.0) {
			lit = mix(lit, atmosphere_color.rgb * (0.2 + sunlight), pow(1.0 - z, 3.0) * 0.6);
		}
		float inside = 1.0 - smoothstep(1.0 - aa / body_fraction, 1.0, rs);
		result = mix(result, vec4(lit, 1.0), inside);
	}

	COLOR = result;
}

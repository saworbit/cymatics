shader_type canvas_item;
render_mode blend_add, unshaded;

// Ambient mote: a soft additive point. The particles node sits at arena
// centre, so |VERTEX.x| in local space is the distance to the centre line;
// motes brighten as they drift toward it.

uniform vec4 tint : source_color = vec4(0.7, 0.55, 1.0, 1.0);
uniform float brightness : hint_range(0.0, 3.0) = 1.0;
uniform float centre_bias : hint_range(0.0, 1.0) = 0.6;

varying float v_centre;

void vertex() {
	v_centre = 1.0 - clamp(abs(VERTEX.x) / 960.0, 0.0, 1.0);
}

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float core = exp(-r * r * 9.0);
	float halo = exp(-r * r * 2.2) * 0.35;
	float near = mix(1.0 - centre_bias, 1.0, pow(v_centre, 2.2));
	float a = (core + halo) * COLOR.a * brightness * near;
	if (a < 0.003) {
		discard;
	}
	vec3 col = tint.rgb * COLOR.rgb * (0.5 + core * 0.9);
	COLOR = vec4(col * a, a);
}

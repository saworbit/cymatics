shader_type canvas_item;
render_mode blend_add, unshaded;

// Directional wedge for the paddle blast. The quad's x axis runs from the
// nozzle (UV.x = 0) outward; the node is rotated to the blast direction.
uniform vec4 tint : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 4.0) = 2.2;
uniform float half_angle : hint_range(0.05, 0.6) = 0.30;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

void fragment() {
	float along = UV.x;
	float across = (UV.y - 0.5) * 2.0;
	float p = clamp(progress, 0.0, 1.0);
	// Wedge silhouette: half width grows linearly from the apex.
	float w = 0.06 + along * half_angle * 2.0;
	float edge = smoothstep(w, w - 0.12, abs(across));
	// Expanding front: only the part behind the front is lit, with a hot rim at the front.
	float front = 0.15 + p * 0.95;
	float behind = smoothstep(front, front - 0.25, along);
	float rim = exp(-abs(along - front) * 18.0) * 1.6;
	// Radial streaks so the wedge reads as a burst, not a flat triangle.
	float ang = across / max(w, 0.001);
	float streak = pow(abs(sin(ang * 9.0 + hash(vec2(floor(ang * 9.0), 0.0)) * 6.28)), 6.0);
	float apex = exp(-along * 5.0);
	float fade = 1.0 - p;
	fade = fade * sqrt(fade);
	float shape = edge * (behind * (0.45 + streak * 0.55) * (1.0 - along * 0.6) + rim * edge);
	vec3 col = mix(tint.rgb, vec3(1.0, 0.98, 0.9), apex * 0.8 + rim * 0.25);
	float a = clamp(shape * fade, 0.0, 1.0);
	COLOR = vec4(col * shape * fade * intensity, a);
}

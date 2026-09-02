shader_type canvas_item;
render_mode blend_add, unshaded;

// One-shot goal-line pulse spawned by VFXManager at a goal. The quad hugs the
// goal line; `side` flips which edge is the wall (0 = left wall at UV.x 0,
// 1 = right wall at UV.x 1). Distinct from goal_wall.gdshader (persistent membrane).
uniform vec4 tint : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float hit_v : hint_range(0.0, 1.0) = 0.5;
uniform int side : hint_range(0, 1) = 0;
uniform float intensity : hint_range(0.0, 4.0) = 2.4;

void fragment() {
	float x = (side == 0) ? UV.x : 1.0 - UV.x;
	float p = clamp(progress, 0.0, 1.0);
	float fade = 1.0 - p;
	fade *= fade;
	// Sheet that lights the whole wall, brightest at the line.
	float sheet = exp(-x * 6.0);
	// Ripple ring expanding along the wall from the impact point.
	float dy = abs(UV.y - hit_v);
	float r = p * 0.9;
	float ring = exp(-pow((dy - r) * 14.0, 2.0)) * (1.0 - x * 0.7);
	// Local bloom at the impact point that dies faster than the sheet.
	float spot = exp(-dy * dy * 60.0) * exp(-x * 3.0) * (1.0 - p) * 1.8;
	float e = sheet * 0.6 + ring * 0.9 + spot;
	vec3 col = mix(tint.rgb, vec3(1.0, 0.98, 0.92), spot * 0.5);
	COLOR = vec4(col * e * fade * intensity, clamp(e * fade, 0.0, 1.0));
}

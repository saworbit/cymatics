shader_type canvas_item;
render_mode blend_mix, unshaded;

// Expressive anime character face. Large sparkling eyes, cute animated mouth, and dynamic mood emotes.
uniform vec2 look = vec2(0.0);
uniform float blink : hint_range(0.0, 1.0) = 0.0;
uniform float mouth : hint_range(0.0, 6.0) = 1.0;
uniform float lid : hint_range(0.0, 1.0) = 0.0;
uniform float brow : hint_range(-1.0, 1.0) = 0.0;
uniform float flip : hint_range(0.0, 1.0) = 0.0;
uniform float dizzy : hint_range(0.0, 1.0) = 0.0;
uniform float blush : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pupil_color : source_color = vec4(0.06, 0.08, 0.16, 1.0);
uniform vec4 mouth_color : source_color = vec4(0.85, 0.22, 0.35, 1.0);

float circle(vec2 p, float r) {
	return 1.0 - smoothstep(r - 0.02, r + 0.01, length(p));
}

void fragment() {
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	// Canvas UVs have Y-down. Flip so +Y is toward the forehead.
	vec2 p = (uv - vec2(0.5)) * vec2(2.05, -2.05);

	float spin = dizzy * TIME * 8.0;
	vec2 look_off = look * vec2(0.08, -0.06);
	if (dizzy > 0.4) {
		look_off = vec2(cos(spin), sin(spin)) * 0.08;
	}

	// 1. Eyes
	vec2 el = vec2(-0.32, 0.14) + look_off * 0.2;
	vec2 er = vec2(0.32, 0.14) + look_off * 0.2;
	float eye_h = mix(0.24, 0.03, clamp(blink + lid * 0.6, 0.0, 1.0));
	float eye_w = 0.21;
	
	// White Sclera
	float white_l = 1.0 - smoothstep(0.0, 0.035, length((p - el) / vec2(eye_w, eye_h)) - 1.0);
	float white_r = 1.0 - smoothstep(0.0, 0.035, length((p - er) / vec2(eye_w, eye_h)) - 1.0);
	float whites = max(white_l, white_r);
	
	// Outer Eye Rim
	float ring_l = 1.0 - smoothstep(0.0, 0.04, length((p - el) / vec2(eye_w + 0.04, eye_h + 0.04)) - 1.0);
	float ring_r = 1.0 - smoothstep(0.0, 0.04, length((p - er) / vec2(eye_w + 0.04, eye_h + 0.04)) - 1.0);
	float rings = max(ring_l, ring_r);

	// Pupils & Highlights
	vec2 pl = el + look_off;
	vec2 pr = er + look_off;
	float pupil_r = mix(0.11, 0.08, lid);
	float pup_l = circle(p - pl, pupil_r);
	float pup_r = circle(p - pr, pupil_r);
	float shine_l1 = circle(p - pl - vec2(-0.035, 0.04), 0.038);
	float shine_r1 = circle(p - pr - vec2(-0.035, 0.04), 0.038);
	float shine_l2 = circle(p - pl - vec2(0.035, -0.035), 0.02);
	float shine_r2 = circle(p - pr - vec2(0.035, -0.035), 0.02);
	float pupils = max(pup_l, pup_r) * step(0.08, eye_h);
	float shine = max(max(shine_l1, shine_r1), max(shine_l2, shine_r2)) * step(0.08, eye_h);

	// 2. Brows (Only rendered during active emotional expressions, hidden during idle)
	float brows = 0.0;
	if (abs(brow) > 0.08) {
		float brow_y = 0.38 + brow * 0.06;
		float brow_ang = brow * 0.22;
		vec2 bl = p - vec2(-0.32, brow_y);
		vec2 br = p - vec2(0.32, brow_y);
		bl = vec2(bl.x * cos(brow_ang) - bl.y * sin(brow_ang), bl.x * sin(brow_ang) + bl.y * cos(brow_ang));
		br = vec2(br.x * cos(-brow_ang) - br.y * sin(-brow_ang), br.x * sin(-brow_ang) + br.y * cos(-brow_ang));
		float brow_l = (1.0 - smoothstep(0.0, 0.035, abs(bl.y) - 0.025)) * (1.0 - smoothstep(0.14, 0.20, abs(bl.x)));
		float brow_r = (1.0 - smoothstep(0.0, 0.035, abs(br.y) - 0.025)) * (1.0 - smoothstep(0.14, 0.20, abs(br.x)));
		brows = max(brow_l, brow_r) * clamp(abs(brow) * 1.5, 0.0, 1.0);
	}

	// 3. Cute Expressive Mouth
	vec2 m = p - vec2(0.0, -0.22);
	float mshape = mouth;
	float mouth_mask = 0.0;
	vec3 m_col = mouth_color.rgb;

	if (mshape < 0.5) {
		// Focus: tiny cute dot mouth
		mouth_mask = circle(m, 0.04);
	} else if (mshape < 1.5) {
		// Idle: soft subtle smile
		float arc = m.y + (m.x * m.x) * 1.8;
		float smile = 1.0 - smoothstep(0.0, 0.04, abs(arc) - 0.025);
		smile *= (1.0 - smoothstep(0.10, 0.16, abs(m.x)));
		mouth_mask = smile;
	} else if (mshape < 2.5) {
		// Happy / Open Smile: filled warm cute mouth with inner tongue
		float arc_top = m.y + (m.x * m.x) * 1.4;
		float open_mouth = (1.0 - smoothstep(0.0, 0.03, arc_top)) * (1.0 - smoothstep(0.0, 0.03, -m.y - 0.08));
		open_mouth *= (1.0 - smoothstep(0.16, 0.24, abs(m.x)));
		mouth_mask = open_mouth;
		if (m.y < -0.03) {
			m_col = mix(m_col, vec3(1.0, 0.55, 0.65), 0.7);
		}
	} else if (mshape < 3.5) {
		// Sad / Pout
		float arc = m.y - (m.x * m.x) * 1.8 + 0.02;
		float pout = 1.0 - smoothstep(0.0, 0.035, abs(arc) - 0.025);
		pout *= (1.0 - smoothstep(0.10, 0.18, abs(m.x)));
		mouth_mask = pout;
	} else if (mshape < 4.5) {
		// Shock / Scare / O-Mouth: filled open circle
		float o_mouth = circle(m, 0.09);
		mouth_mask = o_mouth;
		m_col = mix(vec3(0.15, 0.05, 0.08), m_col, 0.4);
	} else if (mshape < 5.5) {
		// Angry / Grimace: zig-zag grit
		float zig = m.y - 0.03 * sin(m.x * 24.0);
		float grit = 1.0 - smoothstep(0.0, 0.035, abs(zig) - 0.025);
		grit *= (1.0 - smoothstep(0.14, 0.22, abs(m.x)));
		mouth_mask = grit;
	} else {
		// Smug / Cat smile
		float cat = m.y + (m.x * m.x) * 1.2;
		float smug = 1.0 - smoothstep(0.0, 0.035, abs(cat) - 0.022);
		smug *= (1.0 - smoothstep(0.08, 0.20, m.x + 0.04));
		mouth_mask = smug;
	}

	// 4. Blush (soft pink cheeks)
	float blush_l = circle(p - vec2(-0.36, -0.04), 0.11) * blush * 0.65;
	float blush_r = circle(p - vec2(0.36, -0.04), 0.11) * blush * 0.65;

	vec3 col = vec3(0.0);
	float alpha = 0.0;
	if (rings > 0.04) {
		col = vec3(0.04, 0.05, 0.08);
		alpha = rings;
	}
	if (whites > 0.04) {
		col = mix(col, vec3(1.0, 1.0, 0.98), whites);
		alpha = max(alpha, whites);
	}
	if (pupils > 0.04) {
		col = mix(col, pupil_color.rgb, clamp(pupils, 0.0, 1.0));
		alpha = max(alpha, pupils);
	}
	if (shine > 0.04) {
		col = mix(col, vec3(1.0), shine);
		alpha = max(alpha, shine);
	}
	if (brows > 0.15) {
		col = mix(col, pupil_color.rgb, clamp(brows, 0.0, 1.0));
		alpha = max(alpha, brows);
	}
	if (mouth_mask > 0.12) {
		col = mix(col, m_col, clamp(mouth_mask, 0.0, 1.0));
		alpha = max(alpha, mouth_mask);
	}
	if (blush_l + blush_r > 0.02) {
		col = mix(col, vec3(1.0, 0.4, 0.5), (blush_l + blush_r));
		alpha = max(alpha, (blush_l + blush_r) * 0.75);
	}

	if (alpha < 0.06) {
		discard;
	}
	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}

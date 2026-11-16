shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.84, 0.37, 1.0);
uniform vec2 size = vec2(2.0, 2.0);
uniform float progress = 0.0;
uniform float dashed = 0.0;
uniform float active = 0.0;
uniform float fill_alpha = 0.12;
float sd(vec2 p, vec2 b, float r) { vec2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }
void fragment() {
	vec2 p = (UV - 0.5) * size;
	float d = sd(p, size * 0.5 - 0.05, 0.28);
	float bw = 0.075;
	float border = smoothstep(bw, bw * 0.4, abs(d + bw));
	if (dashed > 0.5) {
		float along = abs(p.x) / size.x > abs(p.y) / size.y ? p.y : p.x;
		border *= step(0.42, fract(along * 2.2 - TIME * 0.6));
	}
	float inside = step(d, 0.0);
	float fy = (0.5 - UV.y);
	float filled = step(fy, progress - 0.5) * inside;
	float pulse = 0.5 + 0.5 * sin(TIME * 6.0);
	float halo = smoothstep(0.16, 0.0, abs(d + bw)) * (1.0 - border);
	float fill = inside * (fill_alpha + 0.12 * active) + filled * 0.38;
	vec3 c = col.rgb * (1.0 + 0.25 * active * pulse);
	vec3 base = mix(vec3(0.05, 0.03, 0.01), c, clamp(fill * 2.5, 0.0, 1.0));
	ALBEDO = mix(base, c, border);
	ALPHA = clamp(max(border * (0.92 + 0.08 * pulse * active), max(halo * 0.45, fill)), 0.0, 1.0) * col.a;
}

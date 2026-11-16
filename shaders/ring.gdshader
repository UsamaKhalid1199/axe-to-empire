shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float progress = 0.0;
uniform vec4 col : source_color = vec4(1.0, 0.8, 0.3, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	float a = atan(p.x, -p.y) / 6.28318 + 0.5;
	float ring = smoothstep(0.5, 0.47, r) * smoothstep(0.30, 0.33, r);
	float on = step(a, progress);
	vec3 c = mix(vec3(0.07, 0.05, 0.04), col.rgb, on);
	float disc = smoothstep(0.31, 0.29, r) * 0.55;
	ALBEDO = c;
	ALPHA = max(ring * (0.65 + 0.35 * on), disc * 0.0 ) ;
}

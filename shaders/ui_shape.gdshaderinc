uniform vec2 size = vec2(100.0);
uniform float pad = 20.0;
uniform float radius = 18.0;
uniform vec4 top : source_color = vec4(0.07, 0.05, 0.035, 0.7);
uniform vec4 bottom : source_color = vec4(0.07, 0.05, 0.035, 0.7);
uniform vec4 border : source_color = vec4(1.0, 1.0, 1.0, 0.14);
uniform float border_w = 1.5;
uniform float glass = 1.0;
uniform float shadow = 0.45;
uniform float highlight = 0.0;
uniform float dim = 0.0;
#ifndef NO_GLASS
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
#endif
float sd(vec2 p, vec2 b, float r) { vec2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }
void fragment() {
	vec2 full = size + 2.0 * pad;
	vec2 p = UV * full - full * 0.5;
	float d = sd(p, size * 0.5, radius);
	float inside = clamp(0.5 - d, 0.0, 1.0);
	float t = clamp((p.y + size.y * 0.5) / size.y, 0.0, 1.0);
	vec4 c = mix(top, bottom, t);
#ifndef NO_GLASS
	if (glass > 0.5) {
		vec3 bg = textureLod(screen_tex, SCREEN_UV, 4.0).rgb;
		c.rgb = mix(bg, c.rgb, c.a);
		c.a = 1.0;
	}
#else
	if (glass > 0.5) { c.a = min(1.0, c.a + 0.12); }
#endif
	float hl = (1.0 - smoothstep(0.0, 0.5, t)) * highlight;
	c.rgb += vec3(hl * 0.35);
	c.rgb = mix(c.rgb, vec3(0.32, 0.30, 0.28), dim);
	float bm = clamp(1.0 - abs(d + border_w * 0.5) / border_w, 0.0, 1.0);
	c.rgb = mix(c.rgb, border.rgb, bm * border.a);
	float ds = sd(p - vec2(0.0, 6.0), size * 0.5, radius);
	float sh = (1.0 - smoothstep(-4.0, pad, ds)) * shadow;
	vec4 outc = mix(vec4(0.0, 0.0, 0.0, sh), c, inside);
	COLOR = outc;
}

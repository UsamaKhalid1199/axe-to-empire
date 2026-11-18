shader_type spatial;
// shaders/ground.gdshader plus a tint blend at plot edges: along the one road, two plots with different
// themes (snowy lodge, green lakeside, autumn smokehouse) meet at x = edge. Each side fades its grass/dirt tint
// halfway toward the other's over `blend_w` metres, so both planes have the same colour at the shared edge.
uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 world_min = vec2(-40.0);
uniform vec2 world_size = vec2(80.0);
uniform bool lite = false;
uniform vec3 dirt_tint : source_color = vec3(1.05, 0.97, 0.9);
uniform vec3 grass_tint : source_color = vec3(0.80, 1.0, 0.55);
uniform float west_x = -100000.0;
uniform vec3 west_grass : source_color = vec3(0.80, 1.0, 0.55);
uniform vec3 west_dirt : source_color = vec3(1.05, 0.97, 0.9);
uniform float east_x = 100000.0;
uniform vec3 east_grass : source_color = vec3(0.80, 1.0, 0.55);
uniform vec3 east_dirt : source_color = vec3(1.05, 0.97, 0.9);
uniform float blend_w = 6.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz * 0.33;
	float n = texture(noise_tex, wpos.xz * 0.025).r;
	float n2 = texture(noise_tex, wpos.xz * 0.11).r;
	float m = texture(mask_tex, (wpos.xz - world_min) / world_size).r;
	m = smoothstep(0.32, 0.68, m + (n2 - 0.5) * 0.55);
	float wb = 0.5 * (1.0 - smoothstep(0.0, blend_w, abs(wpos.x - west_x)));
	float eb = 0.5 * (1.0 - smoothstep(0.0, blend_w, abs(east_x - wpos.x)));
	vec3 gt = mix(mix(grass_tint, west_grass, wb), east_grass, eb);
	vec3 dt = mix(mix(dirt_tint, west_dirt, wb), east_dirt, eb);
	vec3 g = texture(grass_alb, uv).rgb * gt * mix(0.78, 1.18, n);
	g = mix(g, g * vec3(1.12, 1.0, 0.62), smoothstep(0.55, 0.85, n2) * 0.6);
	vec3 d = texture(dirt_alb, uv * 0.7).rgb * dt;
	ALBEDO = mix(g, d, m);
	if (!lite) {
		NORMAL_MAP = mix(texture(grass_nor, uv).rgb, texture(dirt_nor, uv * 0.7).rgb, m);
		NORMAL_MAP_DEPTH = 0.8;
	}
	ROUGHNESS = 0.96;
	SPECULAR = 0.2;
}

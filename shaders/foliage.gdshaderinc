uniform vec3 dark : source_color = vec3(0.05, 0.13, 0.07);
uniform vec3 light : source_color = vec3(0.30, 0.46, 0.20);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float wind = 1.0;
uniform vec2 player_screen = vec2(-9.0);
uniform float player_dist = 0.0;
uniform float aspect = 0.5625;
varying vec3 wpos;
varying float tint;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 o = MODEL_MATRIX[3].xz;
	tint = fract(sin(dot(o, vec2(12.9898, 78.233))) * 43758.5453) * 0.5;
	float h = max(VERTEX.y - 0.8, 0.0) * (1.0 - step(0.5, COLOR.g));
	float w = sin(TIME * 1.4 + wpos.x * 0.35 + wpos.z * 0.27) * 0.025 * h * wind;
	VERTEX.x += w;
	VERTEX.z += w * 0.6;
}
void fragment() {
#ifdef SEE_THROUGH
	vec2 sd = (SCREEN_UV - player_screen) * vec2(1.0, 1.0 / aspect) ;
	float r = length(vec2(sd.x, sd.y * 0.75));
	if (r < 0.16 && -VERTEX.z < player_dist - 0.8) {
		float k = smoothstep(0.16, 0.06, r);
		vec2 fq = mod(floor(FRAGCOORD.xy), 2.0);
		vec2 fq2 = mod(floor(FRAGCOORD.xy * 0.5), 2.0);
		float b2 = fq.x * 2.0 + fq.y * 3.0 - 4.0 * fq.x * fq.y;
		float b2b = fq2.x * 2.0 + fq2.y * 3.0 - 4.0 * fq2.x * fq2.y;
		float bayer = (b2 * 4.0 + b2b + 0.5) / 16.0;
		if (bayer < k * 0.9) { discard; }
	}
#endif
	float n = texture(noise_tex, wpos.xz * 0.45 + vec2(wpos.y * 0.37)).r;
	float n2 = texture(noise_tex, wpos.xz * 2.3 + vec2(wpos.y * 1.7)).r;
	vec3 c = mix(dark, light, 0.3 + 0.7 * COLOR.r) * (0.72 + 0.45 * n) * (0.85 + 0.3 * n2);
	c = mix(c, c * vec3(1.25, 1.08, 0.7), tint);
	c = clamp(c, vec3(0.0), vec3(1.0));
	float trunk = step(0.5, COLOR.g);
	vec3 bark = vec3(0.46, 0.32, 0.21) * (0.6 + 0.6 * n2) * (0.8 + 0.25 * sin(wpos.y * 9.0 + n * 6.0));
	c = mix(c, bark, trunk);
	float cutf = step(0.5, COLOR.b);
	float rr = length(UV);
	vec3 wood = vec3(0.80, 0.62, 0.40) * (0.86 + 0.14 * sin(rr * 38.0 + n * 3.0));
	wood = mix(wood, vec3(0.36, 0.24, 0.15), smoothstep(0.82, 0.95, rr));
	c = mix(c, wood, cutf);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	BACKLIGHT = clamp(c * 0.55, vec3(0.0), vec3(1.0)) * (1.0 - trunk);
}

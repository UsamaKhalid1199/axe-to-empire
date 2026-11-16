shader_type spatial;
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float rings = 0.5 + 0.5 * sin(r * 38.0 + sin(atan(p.y, p.x) * 3.0) * 0.6);
	vec3 inner = vec3(0.86, 0.66, 0.40);
	vec3 ringc = vec3(0.66, 0.44, 0.22);
	vec3 bark = vec3(0.24, 0.15, 0.09);
	vec3 c = mix(inner, ringc, rings * 0.55 + r * 0.25);
	c = mix(c, bark, smoothstep(0.82, 0.9, r));
	ALBEDO = c;
	ROUGHNESS = 0.85;
}

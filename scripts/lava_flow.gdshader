shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// 流动岩浆：动态裂纹与流动纹理，平均亮度保持不变
uniform vec3 base_color : source_color = vec3(0.95, 0.36, 0.08);
uniform vec3 emission_color : source_color = vec3(1.0, 0.46, 0.12);
uniform float emission_energy = 4.2;
uniform float flow_speed = 0.06;
uniform float pattern_scale = 0.12;
uniform vec3 crust_color : source_color = vec3(0.12, 0.04, 0.02);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * noise(p);
		p = p * 2.0 + vec2(11.7, 3.1);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// 以世界坐标的水平面做流动采样，两层反向流动叠加，形成翻滚感
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = world_pos.xz * pattern_scale;
	vec2 flow_a = vec2(TIME * flow_speed, TIME * flow_speed * 0.35);
	vec2 flow_b = vec2(-TIME * flow_speed * 0.6, TIME * flow_speed * 0.8);
	float n1 = fbm(uv + flow_a);
	float n2 = fbm(uv * 1.7 + flow_b);
	float flow = mix(n1, n2, 0.5);

	// 岩浆裂纹：低值处为暗色结壳，高值处为炽热流体
	float crust = smoothstep(0.62, 0.30, flow); // flow 低 -> crust 大
	vec3 albedo = mix(base_color, crust_color, crust * 0.85);
	ALBEDO = albedo;

	// 平均亮度保持不变：调制项均值≈1.0（fbm 均值≈0.5）
	float bright = 0.8 + 0.4 * flow;
	// 裂纹处稍暗，缝隙里仍透出微光
	bright *= mix(1.0, 0.55, crust);
	EMISSION = emission_color * emission_energy * bright;
	ROUGHNESS = mix(0.35, 0.85, crust);
	METALLIC = 0.0;
}

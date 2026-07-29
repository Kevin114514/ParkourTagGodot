shader_type sky;
render_mode use_debanding;

// 下界动态天空：翻涌的暗红云层 + 地平线火光脉动
uniform vec3 top_color : source_color = vec3(0.16, 0.03, 0.02);
uniform vec3 horizon_color : source_color = vec3(0.95, 0.32, 0.08);
uniform vec3 cloud_color : source_color = vec3(0.55, 0.12, 0.03);
uniform float cloud_scale = 3.0;
uniform float cloud_speed = 0.04;
uniform float horizon_glow = 1.6;
// 地平线火光带的柔和度：越小越宽越柔（渐变），越大越窄越锐（硬边）
uniform float horizon_softness = 3.0;

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
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void sky() {
	// 基于视线方向做上下渐变：底部（地平线）偏火光，顶部偏暗红
	float h = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 base = mix(horizon_color, top_color, pow(h, 0.55));

	// 翻涌云层：以视线的 xz 分量做流动的 fbm
	vec2 uv = EYEDIR.xz / max(abs(EYEDIR.y) + 0.15, 0.001);
	vec2 flow = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.6);
	float clouds = fbm(uv * cloud_scale + flow);
	clouds = smoothstep(0.35, 0.85, clouds);
	base = mix(base, cloud_color, clouds * (1.0 - h) * 0.7);

	// 地平线火光脉动：用可调的柔和度替代原来固定的锐利指数，
	// 让火光从地平线向上平缓衰减，避免与远处被雾染色的岩浆形成硬边界。
	float horizon_band = pow(clamp(1.0 - abs(EYEDIR.y), 0.0, 1.0), horizon_softness);
	float pulse = 0.75 + 0.25 * sin(TIME * 0.8);
	base += horizon_color * horizon_band * horizon_glow * pulse;

	COLOR = base;
}

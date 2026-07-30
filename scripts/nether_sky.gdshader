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

// 3D 值噪声：以哈希在整数格点插值，三线性平滑，避免平面投影拉伸产生的方块条纹
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	// 五次平滑插值（Perlin 改进型），比 3t^2-2t^3 更柔、导数连续，云更蓬松
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = hash3(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash3(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	float nxy0 = mix(nx00, nx10, u.y);
	float nxy1 = mix(nx01, nx11, u.y);
	return mix(nxy0, nxy1, u.z);
}

// 3D 分形噪声：6 层叠加 + 轻微旋转错位，减少各层格点对齐产生的方向性条纹
float fbm3(vec3 p) {
	float v = 0.0;
	float amp = 0.5;
	mat3 rot = mat3(
		vec3(0.00, 0.80, 0.60),
		vec3(-0.80, 0.36, -0.48),
		vec3(-0.60, -0.48, 0.64)
	);
	for (int i = 0; i < 6; i++) {
		v += amp * noise3(p);
		p = rot * p * 2.02;
		amp *= 0.5;
	}
	return v;
}

void sky() {
	// 基于视线方向做上下渐变：底部（地平线）偏火光，顶部偏暗红
	float h = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 base = mix(horizon_color, top_color, pow(h, 0.55));

	// 翻涌云层：直接以 3D 视线方向采样 fbm，避免地平线附近的平面投影拉伸（方块感的根源）。
	// 轻微压扁 y 分量，让云在天顶铺展成层状而非球壳，看起来更像真实云层。
	vec3 cdir = vec3(EYEDIR.x, EYEDIR.y * 0.35, EYEDIR.z);
	vec3 flow = vec3(TIME * cloud_speed, 0.0, TIME * cloud_speed * 0.6);
	float clouds = fbm3(cdir * cloud_scale + flow);
	// 再叠一层更细、流动更快的高频细节，打散大团块的硬边，增加蓬松感
	clouds += 0.18 * fbm3(cdir * cloud_scale * 3.1 + flow * 2.3);
	// 柔和的过渡区间，边缘不再是硬切；云量随高度略微衰减但不再死压在下半天空
	clouds = smoothstep(0.42, 0.95, clouds);
	float cloud_cover = clouds * mix(0.55, 0.9, 1.0 - h * 0.6);
	base = mix(base, cloud_color, cloud_cover);

	// 地平线火光脉动：用可调的柔和度替代原来固定的锐利指数，
	// 让火光从地平线向上平缓衰减，避免与远处被雾染色的岩浆形成硬边界。
	float horizon_band = pow(clamp(1.0 - abs(EYEDIR.y), 0.0, 1.0), horizon_softness);
	float pulse = 0.75 + 0.25 * sin(TIME * 0.8);
	base += horizon_color * horizon_band * horizon_glow * pulse;

	COLOR = base;
}

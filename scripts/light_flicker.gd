extends Node
## 挂在 Light3D 下的子节点，运行时驱动父灯的亮度实现频闪/闪烁/脉冲效果。
## 由 MapLoader 根据地图灯光的 "flicker" 字段自动附加。

var target: Light3D
var base_energy: float = 2.6
var mode: String = "flicker"      # flicker(坏灯随机) / strobe(规律频闪) / pulse(缓慢呼吸)
var frequency: float = 9.0        # 频率(Hz)：strobe 开关频率、pulse 呼吸频率、flicker 抖动速度
var min_energy: float = 0.12      # 相对 base 的最低亮度倍率（保留微光，避免全黑死区）
var max_energy: float = 1.0       # 相对 base 的最高亮度倍率

var _t: float = 0.0
var _phase: float = 0.0
var _next_at: float = 0.0

func _ready() -> void:
	target = get_parent() as Light3D
	_phase = randf() * TAU
	_t = randf() * 10.0            # 随机初相，避免所有灯同步闪
	set_process(target != null)

func _process(delta: float) -> void:
	if target == null:
		return
	_t += delta
	match mode:
		"strobe":
			var on := fmod(_t * frequency, 1.0) < 0.5
			target.light_energy = base_energy * (max_energy if on else min_energy)
		"pulse":
			var s := sin(_t * frequency * TAU + _phase) * 0.5 + 0.5
			target.light_energy = base_energy * lerp(min_energy, max_energy, s)
		_:  # flicker：坏灯随机抖动，偶尔近乎熄灭
			if _t >= _next_at:
				_next_at = _t + randf_range(0.03, 0.2) / max(0.1, frequency / 9.0)
				var r := randf()
				var lvl: float
				if r < 0.12:
					lvl = min_energy                                   # 偶尔骤暗
				elif r < 0.3:
					lvl = lerp(min_energy, max_energy, 0.45)           # 半亮
				else:
					lvl = lerp(max_energy * 0.72, max_energy, randf()) # 大部分时间接近全亮
				target.light_energy = base_energy * lvl

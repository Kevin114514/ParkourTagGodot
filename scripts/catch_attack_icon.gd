extends Control

var recovery_ratio := 1.0
var recovery_color := Color(0.5, 1.0, 0.58, 0.9)
var is_disabled := false

func set_cooldown_state(ratio: float, color: Color, hint: String, disabled: bool = false) -> void:
	recovery_ratio = clampf(ratio, 0.0, 1.0)
	recovery_color = color
	is_disabled = disabled
	tooltip_text = hint
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.44
	draw_circle(center, radius, Color(0.025, 0.04, 0.08, 0.7))
	if recovery_ratio > 0.0:
		var segments := maxi(2, ceili(64.0 * recovery_ratio))
		var points := PackedVector2Array([center])
		for index in range(segments + 1):
			var angle := -PI * 0.5 + TAU * recovery_ratio * float(index) / float(segments)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(points, recovery_color)
	draw_arc(center, radius, 0.0, TAU, 72, Color(1.0, 1.0, 1.0, 0.72), 4.0, true)
	var blade := Color(1.0, 1.0, 1.0, 0.95)
	draw_line(center + Vector2(-28.0, 28.0), center + Vector2(25.0, -25.0), blade, 9.0, true)
	draw_line(center + Vector2(-28.0, 14.0), center + Vector2(-13.0, 29.0), blade, 7.0, true)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(18.0, -29.0),
		center + Vector2(35.0, -36.0),
		center + Vector2(28.0, -18.0),
	]), blade)
	if is_disabled:
		var forbidden_radius := radius * 0.92
		var slash_offset := Vector2(forbidden_radius * 0.66, forbidden_radius * 0.66)
		var shadow_color := Color(0.12, 0.0, 0.0, 0.88)
		var forbidden_color := Color(1.0, 0.08, 0.08, 0.98)
		draw_circle(center, forbidden_radius, Color(0.16, 0.0, 0.0, 0.24))
		draw_arc(center, forbidden_radius, 0.0, TAU, 72, shadow_color, 15.0, true)
		draw_line(center - slash_offset, center + slash_offset, shadow_color, 18.0, true)
		draw_arc(center, forbidden_radius, 0.0, TAU, 72, forbidden_color, 10.0, true)
		draw_line(center - slash_offset, center + slash_offset, forbidden_color, 12.0, true)

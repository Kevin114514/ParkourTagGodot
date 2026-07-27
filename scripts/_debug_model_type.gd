extends SceneTree

const SkinAPIRef = preload("res://scripts/skin_api.gd")

func _init() -> void:
	var skin := SkinAPIRef.load_role_skin("runner", "badge2")
	var scene_path := String(skin.get("model_scene", ""))
	print("[debug] model_scene=", scene_path)
	var node := SkinAPIRef.instantiate_skin_model("badge2", scene_path)
	print("[debug] model_node_null=", node == null)
	if node != null:
		print("[debug] model_node_class=", node.get_class())
	quit(0)

extends SceneTree

const MapLoader = preload("res://scripts/map_loader.gd")

func _initialize() -> void:
	var root_node := Node3D.new()
	get_root().add_child(root_node)
	var res: Dictionary = MapLoader.load_map(root_node, "res://maps/dragon_palace.json")
	print("ok=", res["ok"], " error=", res["error"])
	print("name=", res["name"])
	print("runner=", res["runner_spawn"], " tagger=", res["tagger_spawn"])
	if res["map_root"] != null:
		var count := 0
		var bodies := 0
		for c in (res["map_root"] as Node).get_children():
			count += 1
			if c is StaticBody3D:
				bodies += 1
		print("children=", count, " staticbodies=", bodies)
	quit(0)

extends Node3D
## Demo for MapGenerator + RaceGenerator. Open map_demo.tscn and press F6.
##
## Controls:
##   1 / 2 / 3  load grid.png / grid_traffic_lanes.png / grid_traffic_lanes_2.png
##   G          generate a brand-new random city
##   C / P      new circuit / new point-to-point race on the current map
##   M          save the current map image to user:// (for the destination-map scripts)
##   WASD       move camera, Q / E rotate, mouse wheel zoom
##   Drag a PNG file onto the game window to build a map from it.

const PRESET_MAPS := ["res://grid.png", "res://grid_traffic_lanes.png", "res://grid_traffic_lanes_2.png"]

@onready var map: MapGenerator = $MapGenerator
@onready var race: RaceGenerator = $RaceGenerator
@onready var camera: Camera3D = $Camera3D
@onready var info: Label = $UI/Info

var _target := Vector3.ZERO
var _yaw := 0.0
var _distance := 150.0
var _car: MeshInstance3D


func _ready() -> void:
	map.map_generated.connect(_on_map_generated)
	race.race_generated.connect(_on_race_generated)
	race.checkpoint_passed.connect(func(i, body): print("Checkpoint %d passed by %s" % [i, body.name]))
	get_window().files_dropped.connect(_on_files_dropped)
	if map.width > 0:
		_on_map_generated()
		if not race.route.is_empty():
			_on_race_generated()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3:
				map.generate_from_file(PRESET_MAPS[event.keycode - KEY_1])
			KEY_G:
				map.generate_from_image(MapGenerator.make_random_city_image(48, 48))
			KEY_C:
				race.race_type = RaceGenerator.RaceType.CIRCUIT
				race.generate()
			KEY_P:
				race.race_type = RaceGenerator.RaceType.POINT_TO_POINT
				race.generate()
			KEY_M:
				var path := "user://generated_map_%d.png" % Time.get_unix_time_from_system()
				map.source_image.save_png(path)
				print("Saved map to ", ProjectSettings.globalize_path(path))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(20.0, _distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(600.0, _distance * 1.1)


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): move.y -= 1
	if Input.is_key_pressed(KEY_S): move.y += 1
	if Input.is_key_pressed(KEY_A): move.x -= 1
	if Input.is_key_pressed(KEY_D): move.x += 1
	if Input.is_key_pressed(KEY_UP): move.y -= 1
	if Input.is_key_pressed(KEY_DOWN): move.y += 1
	if Input.is_key_pressed(KEY_LEFT): move.x -= 1
	if Input.is_key_pressed(KEY_RIGHT): move.x += 1
	if Input.is_key_pressed(KEY_Q): _yaw += delta * 1.5
	if Input.is_key_pressed(KEY_E): _yaw -= delta * 1.5
	var speed := _distance * 0.8 * delta
	_target += Vector3(move.x, 0, move.y).rotated(Vector3.UP, _yaw) * speed
	_update_camera()


func _update_camera() -> void:
	var offset := Vector3(0, _distance * 0.9, _distance * 0.4).rotated(Vector3.UP, _yaw)
	camera.position = _target + offset
	camera.look_at(_target, Vector3.UP)


func _on_map_generated() -> void:
	_target = map.get_map_center()
	_distance = maxf(map.width, map.height) * map.tile_size * 0.9
	_update_camera()


func _on_race_generated() -> void:
	# A placeholder "car" at the start, facing the driving direction.
	if _car == null:
		_car = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.8, 1.2, 4.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5, 0.0)
		box.material = mat
		_car.mesh = box
		add_child(_car)
	_car.global_transform = race.get_start_transform(0.6)

	var kind := "Circuit" if race.is_circuit else "Point-to-point"
	info.text = ("%s race: %d tiles (%.0f m), %d checkpoints. Map %dx%d.\n" % [
			kind, race.route.size(), race.get_route_length(), race.checkpoint_indices.size(),
			map.width, map.height]
		+ "1/2/3 repo maps · G random city · C circuit · P point-to-point · M save PNG\n"
		+ "WASD/arrows move · Q/E rotate · wheel zoom · drop a PNG on the window to load it")


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		if f.to_lower().ends_with(".png"):
			map.generate_from_file(f)
			return

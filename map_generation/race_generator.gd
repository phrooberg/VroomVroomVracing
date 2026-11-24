class_name RaceGenerator
extends Node3D
## Turns a generated MapGenerator city into a race: a route along the road
## tiles, a start, a finish and checkpoints.
##
## CIRCUIT: picks waypoints spread around the map and joins them into a loop.
## POINT_TO_POINT: picks a start, a far-away finish and a detour point.
## Paths use Godot's AStarGrid2D. Tiles that are already on the route get a
## higher cost, so later legs prefer other streets and the route rarely doubles back.
##
## Result (grid cells): route, checkpoint_indices, get_finish_cell().
## Result (3D): route_world, get_start_transform(), Area3D checkpoints that emit checkpoint_passed.

signal race_generated
## Emitted when a physics body enters checkpoint number `index`.
## The last checkpoint is the finish line (for a circuit it is the start/finish line).
signal checkpoint_passed(index: int, body: Node3D)

enum RaceType { CIRCUIT, POINT_TO_POINT }

@export var map: MapGenerator
@export var race_type: RaceType = RaceType.CIRCUIT
## Build a race automatically whenever the map is (re)generated.
@export var generate_on_map_ready := true
## How many corners the circuit is spread over (more = twistier).
@export_range(3, 12) var circuit_waypoints := 5
## Distance between checkpoints, in tiles.
@export var checkpoint_spacing := 8
## How many random tries to make; the route that overlaps itself least wins.
@export var attempts := 30
@export var show_route := true
## Seed for the race. 0 = different every time.
@export var race_seed := 0

## Road cells the race follows, in order. For a circuit the route loops from the last cell back to the first.
var route: Array[Vector2i] = []
## Same as route, in global 3D coordinates (tile centres).
var route_world := PackedVector3Array()
## Indices into route where checkpoints sit. The last one is the finish.
var checkpoint_indices: Array[int] = []
var is_circuit := false

var _astar: AStarGrid2D
var _main_cells: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()
var _visual: Node3D

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


func _ready() -> void:
	if map and generate_on_map_ready:
		map.map_generated.connect(generate)
		if map.width > 0:
			generate()


## Builds a new race on the current map. Returns false if no route was found.
func generate() -> bool:
	return generate_race(race_type)


func generate_race(type: RaceType) -> bool:
	if map == null or map.width == 0:
		push_error("RaceGenerator: no generated map")
		return false
	if race_seed != 0:
		_rng.seed = race_seed
	else:
		_rng.randomize()
	_setup_grid()
	if _main_cells.size() < 8:
		push_error("RaceGenerator: map has too few road tiles")
		return false

	is_circuit = type == RaceType.CIRCUIT
	var best: Array[Vector2i] = []
	var best_score := INF
	for i in attempts:
		var candidate: Array[Vector2i] = _try_circuit() if is_circuit else _try_point_to_point()
		if candidate.size() < 8:
			continue
		# Lower is better: mostly self-overlap, slight preference for longer routes.
		var score := _overlap_ratio(candidate, is_circuit) - candidate.size() * 0.0005
		if score < best_score:
			best_score = score
			best = candidate
	if best.is_empty():
		push_error("RaceGenerator: could not find a route")
		return false

	route = best
	route_world = PackedVector3Array()
	for c in route:
		route_world.append(map.grid_to_world(c))
	_place_checkpoints()
	_build_visuals()
	race_generated.emit()
	return true


## Where a car should spawn: on the first route tile, facing along the route.
func get_start_transform(height := 0.5) -> Transform3D:
	var from := route_world[0] + Vector3.UP * height
	var to := route_world[1] + Vector3.UP * height
	return Transform3D(Basis.looking_at(to - from, Vector3.UP), from)


## The finish tile. Can be used as the destination for a destination-map.
func get_finish_cell() -> Vector2i:
	return route[0] if is_circuit else route[route.size() - 1]


## Total length of the route in metres (one lap for a circuit).
func get_route_length() -> float:
	var n := route.size() if is_circuit else route.size() - 1
	return n * map.tile_size


# --- Pathfinding ------------------------------------------------------------

func _setup_grid() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, map.width, map.height)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()
	for y in map.height:
		for x in map.width:
			if not map.is_road(Vector2i(x, y)):
				_astar.set_point_solid(Vector2i(x, y))
	_main_cells = _largest_component()


## Only use the biggest connected road network, so every waypoint is reachable.
func _largest_component() -> Array[Vector2i]:
	var seen := {}
	var best: Array[Vector2i] = []
	for start in map.get_road_cells():
		if seen.has(start):
			continue
		var comp: Array[Vector2i] = [start]
		seen[start] = true
		var head := 0
		while head < comp.size():
			var c := comp[head]
			head += 1
			for d in DIRS:
				var n := c + d
				if map.is_road(n) and not seen.has(n):
					seen[n] = true
					comp.append(n)
		if comp.size() > best.size():
			best = comp
	return best


func _bfs_distances(start: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in DIRS:
			var n := c + d
			if map.is_road(n) and not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	return dist


func _reset_weights() -> void:
	_astar.fill_weight_scale_region(_astar.region, 1.0)


## Shortest path a -> b, then make those tiles (and their neighbours) expensive.
func _leg(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var path := _astar.get_id_path(a, b)
	for c in path:
		for d in DIRS:
			var n := c + d
			if map.is_road(n) and _astar.get_point_weight_scale(n) < 4.0:
				_astar.set_point_weight_scale(n, 4.0)
	for c in path:
		_astar.set_point_weight_scale(c, 12.0)
	return path


func _join(legs_points: Array[Vector2i]) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	for i in legs_points.size() - 1:
		var leg := _leg(legs_points[i], legs_points[i + 1])
		if leg.is_empty():
			return []
		if not path.is_empty():
			leg.remove_at(0)
		path.append_array(leg)
	return path


func _nearest_main_cell(target: Vector2) -> Vector2i:
	var best := _main_cells[0]
	var best_d := INF
	for c in _main_cells:
		var d := target.distance_squared_to(Vector2(c))
		if d < best_d:
			best_d = d
			best = c
	return best


func _try_circuit() -> Array[Vector2i]:
	_reset_weights()
	var center := Vector2(map.width, map.height) * 0.5
	var start_angle := _rng.randf() * TAU
	var n := circuit_waypoints
	var points: Array[Vector2i] = []
	for i in n:
		var angle := start_angle + i * TAU / n + _rng.randf_range(-0.3, 0.3) * TAU / n
		var r := _rng.randf_range(0.4, 0.95)
		var target := center + Vector2(cos(angle) * center.x * r, sin(angle) * center.y * r)
		var cell := _nearest_main_cell(target)
		if not points.has(cell):
			points.append(cell)
	if points.size() < 3:
		return []
	points.append(points[0])
	var path := _join(points)
	if path.is_empty():
		return []
	path.remove_at(path.size() - 1)  # Same tile as path[0].
	return _remove_backtracks(path, true)


func _try_point_to_point() -> Array[Vector2i]:
	_reset_weights()
	var start := _main_cells[_rng.randi_range(0, _main_cells.size() - 1)]
	var dist := _bfs_distances(start)
	var max_d := 0
	for c in dist:
		max_d = maxi(max_d, dist[c])
	var far: Array[Vector2i] = []
	var middle: Array[Vector2i] = []
	for c in dist:
		var d: int = dist[c]
		if d >= max_d * 0.75:
			far.append(c)
		elif d >= max_d * 0.3:
			middle.append(c)
	if far.is_empty() or middle.is_empty():
		return []
	var finish := far[_rng.randi_range(0, far.size() - 1)]
	var via := middle[_rng.randi_range(0, middle.size() - 1)]
	var points: Array[Vector2i] = [start, via, finish]
	return _remove_backtracks(_join(points), false)


## Removes dead-end spikes such as A -> B -> A, which can appear where two legs meet.
func _remove_backtracks(path: Array[Vector2i], loop: bool) -> Array[Vector2i]:
	var changed := true
	while changed:
		changed = false
		var out: Array[Vector2i] = []
		for c in path:
			if out.size() >= 2 and out[out.size() - 2] == c:
				out.pop_back()
				changed = true
			elif out.is_empty() or out.back() != c:
				out.append(c)
		if loop:
			while out.size() >= 3 and (out.back() == out[0] or out.back() == out[1]):
				if out.back() == out[0]:
					out.pop_back()
				else:
					out.pop_front()
				changed = true
		path = out
	return path


## Share of route tiles that sit on or next to another, unrelated part of the route.
func _overlap_ratio(path: Array[Vector2i], loop: bool) -> float:
	var where := {}
	for i in path.size():
		if not where.has(path[i]):
			where[path[i]] = []
		where[path[i]].append(i)
	var n := path.size()
	var bad := 0
	for i in n:
		var hit := false
		for d in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var cell: Vector2i = path[i] + d
			if not where.has(cell):
				continue
			for j in where[cell]:
				var gap := absi(i - j)
				if loop:
					gap = mini(gap, n - gap)
				if gap > 3:
					hit = true
					break
			if hit:
				break
		if hit:
			bad += 1
	return float(bad) / n


func _place_checkpoints() -> void:
	checkpoint_indices.clear()
	var spacing := maxi(2, checkpoint_spacing)
	var i := spacing
	while i < route.size() - spacing / 2:
		checkpoint_indices.append(i)
		i += spacing
	# Finish line: the last tile, or back at the start for a circuit.
	checkpoint_indices.append(0 if is_circuit else route.size() - 1)


# --- 3D visuals and checkpoint areas ----------------------------------------

func _route_dir(i: int) -> Vector3:
	var n := route_world.size()
	var a: Vector3 = route_world[maxi(i - 1, 0)] if not is_circuit else route_world[(i - 1 + n) % n]
	var b: Vector3 = route_world[mini(i + 1, n - 1)] if not is_circuit else route_world[(i + 1) % n]
	var d := b - a
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


func _build_visuals() -> void:
	if _visual:
		remove_child(_visual)
		_visual.queue_free()
	_visual = Node3D.new()
	_visual.name = "Race"
	_visual.top_level = true  # Children use global coordinates.
	add_child(_visual)

	var tile := map.tile_size
	if show_route:
		_build_route_line(tile)

	for k in checkpoint_indices.size():
		var idx := checkpoint_indices[k]
		var is_finish := k == checkpoint_indices.size() - 1
		_add_checkpoint(k, route_world[idx], _route_dir(idx), tile, is_finish)

	_add_marker(route_world[0], Color(0.1, 0.9, 0.2), "START", tile)
	if not is_circuit:
		_add_marker(route_world[route_world.size() - 1], Color(0.95, 0.15, 0.1), "FINISH", tile)


func _build_route_line(tile: float) -> void:
	var n := route_world.size()
	var segs := n if is_circuit else n - 1
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = segs
	for i in segs:
		var a := route_world[i] + Vector3.UP * 0.15
		var b := route_world[(i + 1) % n] + Vector3.UP * 0.15
		var basis := Basis.looking_at(b - a, Vector3.UP) * Basis.from_scale(Vector3(tile * 0.4, 0.1, tile * 1.05))
		mm.set_instance_transform(i, Transform3D(basis, (a + b) * 0.5))
		# Green at the start fading to red at the end shows the driving direction.
		mm.set_instance_color(i, Color(0.1, 0.9, 0.2).lerp(Color(0.95, 0.15, 0.1), float(i) / segs))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "RouteLine"
	mmi.multimesh = mm
	_visual.add_child(mmi)


func _add_checkpoint(index: int, pos: Vector3, dir: Vector3, tile: float, is_finish: bool) -> void:
	var area := Area3D.new()
	area.name = "Checkpoint%d" % index
	area.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
	var shape := BoxShape3D.new()
	# 3 tiles wide so it covers a 2-lane road even if the route uses the outer lane.
	shape.size = Vector3(tile * 3.0, 4.0, tile * 0.5)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 2.0
	area.add_child(col)
	area.body_entered.connect(func(body: Node3D):
		if not body is StaticBody3D:  # Ignore buildings and walls, only report cars.
			checkpoint_passed.emit(index, body))

	var mesh := BoxMesh.new()
	mesh.size = Vector3(tile * 3.0, 0.15, tile * 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1) if is_finish else Color(0.2, 0.8, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = 0.08
	area.add_child(mi)
	_visual.add_child(area)


func _add_marker(pos: Vector3, color: Color, text: String, tile: float) -> void:
	var pillar := BoxMesh.new()
	pillar.size = Vector3(tile * 0.3, 6.0, tile * 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pillar.material = mat
	var mi := MeshInstance3D.new()
	mi.name = text
	mi.mesh = pillar
	mi.position = pos + Vector3.UP * 3.0
	_visual.add_child(mi)

	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 96
	label.outline_size = 16
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos + Vector3.UP * 7.0
	_visual.add_child(label)

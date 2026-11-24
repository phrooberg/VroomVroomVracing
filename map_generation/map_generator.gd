class_name MapGenerator
extends Node3D
## Builds a simple 3D city from a PNG image at runtime.
##
## Pixel rules (one pixel = one tile):
##   - black (or very dark / transparent) = building
##   - anything else = road (white, or the lane colours used by destmap_traffic.gd)
## The top of the image is north, which is -Z in Godot. So the traffic colour
## blue (northbound) drives towards -Z, yellow (southbound) towards +Z,
## red (eastbound) towards +X and green (westbound) towards -X.
##
## Usage: put this node in a scene, pick a PNG in "Map Texture", run.
## From code: generate_from_texture(), generate_from_file() or generate_from_image().

signal map_generated

@export var map_texture: Texture2D
@export var generate_on_ready := true
## Size of one pixel/tile in metres.
@export var tile_size := 4.0
@export var building_min_height := 4.0
@export var building_max_height := 14.0
## Large black areas are split into buildings of at most this many tiles per side.
@export var max_building_tiles := 4
## Tint road tiles with the lane colour from the PNG (useful for debugging traffic lanes).
@export var show_lane_colors := true
## Pixels whose brightest channel is at or below this count as black (building).
@export_range(0.0, 1.0) var dark_threshold := 0.1
## Seed for building heights. 0 = different every time.
@export var map_seed := 0

const ROAD_COLOR := Color(0.22, 0.22, 0.24)
const GROUND_COLOR := Color(0.45, 0.45, 0.42)
const BUILDING_COLOR := Color(0.62, 0.6, 0.57)

var width := 0
var height := 0
## 1 = road, 0 = building. Index with y * width + x (same layout as destmap.gd).
var road := PackedByteArray()
## The image the current map was built from.
var source_image: Image

var _built: Node3D


func _ready() -> void:
	if generate_on_ready and map_texture:
		generate_from_texture(map_texture)


# --- Public API -------------------------------------------------------------

func generate_from_texture(tex: Texture2D) -> void:
	generate_from_image(tex.get_image())


## Loads a PNG from res://, user:// or any absolute path and builds the map.
func generate_from_file(path: String) -> bool:
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
	if img == null:
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		push_error("MapGenerator: could not load image '%s'" % path)
		return false
	generate_from_image(img)
	return true


func generate_from_image(img: Image) -> void:
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	source_image = img
	width = img.get_width()
	height = img.get_height()

	road.resize(width * height)
	for y in height:
		for x in width:
			road[y * width + x] = 0 if _is_building_color(img.get_pixel(x, y)) else 1

	clear_map()
	_built = Node3D.new()
	_built.name = "GeneratedMap"
	add_child(_built)

	var rng := RandomNumberGenerator.new()
	if map_seed != 0:
		rng.seed = map_seed
	else:
		rng.randomize()

	_build_ground()
	_build_roads()
	_build_buildings(rng)
	_build_walls()
	_build_north_marker()
	map_generated.emit()


func clear_map() -> void:
	if _built:
		remove_child(_built)
		_built.queue_free()
		_built = null


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func is_road(cell: Vector2i) -> bool:
	return is_inside(cell) and road[cell.y * width + cell.x] == 1


func get_road_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in height:
		for x in width:
			if road[y * width + x] == 1:
				cells.append(Vector2i(x, y))
	return cells


## Centre of a tile in global coordinates.
func grid_to_world(cell: Vector2i, y := 0.0) -> Vector3:
	var local := Vector3((cell.x + 0.5) * tile_size, y, (cell.y + 0.5) * tile_size)
	return global_transform * local if is_inside_tree() else local


## Tile that contains a global position.
func world_to_grid(pos: Vector3) -> Vector2i:
	var local := global_transform.affine_inverse() * pos if is_inside_tree() else pos
	return Vector2i(floori(local.x / tile_size), floori(local.z / tile_size))


func get_map_center() -> Vector3:
	var local := Vector3(width * tile_size * 0.5, 0.0, height * tile_size * 0.5)
	return global_transform * local if is_inside_tree() else local


# --- Building the scene -----------------------------------------------------

func _is_building_color(c: Color) -> bool:
	return c.a < 0.5 or maxf(c.r, maxf(c.g, c.b)) <= dark_threshold


func _make_material(color: Color, use_vertex_color := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = use_vertex_color
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	return mat


func _add_box_collider(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = center
	body.add_child(col)


func _build_ground() -> void:
	var size := Vector3(width * tile_size, 0.2, height * tile_size)
	var center := Vector3(size.x * 0.5, -0.1, size.z * 0.5)

	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _make_material(GROUND_COLOR)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.position = center
	_built.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	_built.add_child(body)
	_add_box_collider(body, center, size)


func _build_roads() -> void:
	var count := 0
	for v in road:
		count += v

	var plane := PlaneMesh.new()
	plane.size = Vector2(tile_size, tile_size)
	plane.material = _make_material(Color.WHITE, true)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plane
	mm.instance_count = count

	var i := 0
	for y in height:
		for x in width:
			if road[y * width + x] == 0:
				continue
			var pos := Vector3((x + 0.5) * tile_size, 0.01, (y + 0.5) * tile_size)
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
			var col := ROAD_COLOR
			var px := source_image.get_pixel(x, y)
			if show_lane_colors and not px.is_equal_approx(Color.WHITE):
				col = ROAD_COLOR.lerp(px, 0.25)
			mm.set_instance_color(i, col)
			i += 1

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Roads"
	mmi.multimesh = mm
	_built.add_child(mmi)


## Merges black pixels into rectangles (at most max_building_tiles per side)
## and turns each rectangle into one box building.
func _build_buildings(rng: RandomNumberGenerator) -> void:
	var rects: Array[Rect2i] = []
	var used := PackedByteArray()
	used.resize(width * height)
	var max_tiles := maxi(1, max_building_tiles)

	for y in height:
		for x in width:
			var idx := y * width + x
			if road[idx] == 1 or used[idx] == 1:
				continue
			# Grow right.
			var w := 1
			while w < max_tiles and x + w < width and road[idx + w] == 0 and used[idx + w] == 0:
				w += 1
			# Grow down while the whole row is free building space.
			var h := 1
			while h < max_tiles and y + h < height:
				var row_ok := true
				for dx in w:
					var j := (y + h) * width + x + dx
					if road[j] == 1 or used[j] == 1:
						row_ok = false
						break
				if not row_ok:
					break
				h += 1
			for dy in h:
				for dx in w:
					used[(y + dy) * width + x + dx] = 1
			rects.append(Rect2i(x, y, w, h))

	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _make_material(Color.WHITE, true)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = rects.size()

	var body := StaticBody3D.new()
	body.name = "Buildings"
	_built.add_child(body)

	var inset := tile_size * 0.05
	for i in rects.size():
		var r := rects[i]
		var h := rng.randf_range(building_min_height, building_max_height)
		var size := Vector3(r.size.x * tile_size - inset * 2.0, h, r.size.y * tile_size - inset * 2.0)
		var center := Vector3((r.position.x + r.size.x * 0.5) * tile_size, h * 0.5,
				(r.position.y + r.size.y * 0.5) * tile_size)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(size), center))
		var shade := rng.randf_range(0.8, 1.1)
		mm.set_instance_color(i, Color(BUILDING_COLOR.r * shade, BUILDING_COLOR.g * shade, BUILDING_COLOR.b * shade))
		_add_box_collider(body, center, size)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BuildingMeshes"
	mmi.multimesh = mm
	body.add_child(mmi)


## Invisible walls around the map so cars cannot drive off the edge.
func _build_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "EdgeWalls"
	_built.add_child(body)
	var sx := width * tile_size
	var sz := height * tile_size
	var wall_h := 10.0
	var t := 1.0
	_add_box_collider(body, Vector3(sx * 0.5, wall_h * 0.5, -t * 0.5), Vector3(sx, wall_h, t))
	_add_box_collider(body, Vector3(sx * 0.5, wall_h * 0.5, sz + t * 0.5), Vector3(sx, wall_h, t))
	_add_box_collider(body, Vector3(-t * 0.5, wall_h * 0.5, sz * 0.5), Vector3(t, wall_h, sz))
	_add_box_collider(body, Vector3(sx + t * 0.5, wall_h * 0.5, sz * 0.5), Vector3(t, wall_h, sz))


## A blue "N" just outside the north edge, so you can see which way is north.
func _build_north_marker() -> void:
	var label := Label3D.new()
	label.name = "NorthMarker"
	label.text = "N"
	label.modulate = Color(0.2, 0.4, 1.0)
	label.font_size = 256
	label.pixel_size = 0.02 * tile_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(width * tile_size * 0.5, 6.0, -tile_size * 3.0)
	_built.add_child(label)


# --- Random maps ------------------------------------------------------------

## Makes a random grid-city PNG in the same style as the repo's grid images:
## 2-tile-wide roads, black border. With lanes = true the roads get the traffic
## colours used by destmap_traffic.gd (blue N, yellow S, green W, red E, white crossings).
## Save it with img.save_png("user://my_map.png") or pass it to generate_from_image().
static func make_random_city_image(w := 48, h := 48, seed_value := 0, lanes := true,
		remove_fraction := 0.25) -> Image:
	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var xs := _road_lines(w, rng)
	var ys := _road_lines(h, rng)

	# Each segment: [Rect2i, horizontal]
	var segments: Array = []
	for y in ys:
		for i in xs.size() - 1:
			segments.append([Rect2i(xs[i] + 2, y, xs[i + 1] - xs[i] - 2, 2), true])
	for x in xs:
		for i in ys.size() - 1:
			segments.append([Rect2i(x, ys[i] + 2, 2, ys[i + 1] - ys[i] - 2), false])

	for x in xs:
		for y in ys:
			img.fill_rect(Rect2i(x, y, 2, 2), Color.WHITE)
	for seg in segments:
		_paint_segment(img, seg[0], seg[1], lanes)

	# Remove some street segments for variety, but keep every road connected.
	segments.shuffle()
	var to_remove := int(segments.size() * remove_fraction)
	for seg in segments:
		if to_remove <= 0:
			break
		img.fill_rect(seg[0], Color.BLACK)
		if _is_connected(img):
			to_remove -= 1
		else:
			_paint_segment(img, seg[0], seg[1], lanes)
	return img


static func _road_lines(size: int, rng: RandomNumberGenerator) -> Array[int]:
	var lines: Array[int] = [1]
	var last := size - 3
	while true:
		var next: int = lines.back() + 2 + rng.randi_range(5, 11)
		if next > last:
			break
		lines.append(next)
	if lines.size() > 1 and last - lines.back() < 5:
		lines[lines.size() - 1] = last
	elif lines.back() != last:
		lines.append(last)
	return lines


static func _paint_segment(img: Image, r: Rect2i, horizontal: bool, lanes: bool) -> void:
	if not lanes:
		img.fill_rect(r, Color.WHITE)
	elif horizontal:
		img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 1), Color.GREEN)  # westbound
		img.fill_rect(Rect2i(r.position.x, r.position.y + 1, r.size.x, 1), Color.RED)  # eastbound
	else:
		img.fill_rect(Rect2i(r.position.x, r.position.y, 1, r.size.y), Color.YELLOW)  # southbound
		img.fill_rect(Rect2i(r.position.x + 1, r.position.y, 1, r.size.y), Color.BLUE)  # northbound


static func _is_connected(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var total := 0
	var start := Vector2i(-1, -1)
	for y in h:
		for x in w:
			if img.get_pixel(x, y) != Color.BLACK:
				total += 1
				if start.x < 0:
					start = Vector2i(x, y)
	if total == 0:
		return false
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or seen.has(n):
				continue
			if img.get_pixelv(n) != Color.BLACK:
				seen[n] = true
				queue.append(n)
	return seen.size() == total

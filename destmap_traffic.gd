extends Sprite2D
@export var _texture: Texture2D

var x_size = 0
var y_size = 0

var destmap_array = []

func get_sqr(x: int, y: int) -> float:
	var idx = (y * x_size) + x
	return destmap_array[idx]

func get_sqr_v(v : Vector2i) -> float:
	var idx = (v.y * x_size) + v.x
	return destmap_array[idx]

func set_sqr(x: int, y: int, val: float):
	var idx = (y * x_size) + x
	destmap_array[idx] = val
	
func set_sqr_v(v : Vector2i, val: float):
	var idx = (v.y * x_size) + v.x
	destmap_array[idx] = val
	
func find_random_destination() -> Vector2i:
	var dest = Vector2i.ZERO
	while (true):
		dest.x = randi() % x_size
		dest.y = randi() % y_size
		if(get_sqr(dest.x, dest.y) != -1):
			break # Break if valid square
	return dest

var N = Vector2i(0,-1)
var cN = Color.BLUE
var S = Vector2i(0,1)
var cS = Color.YELLOW
var W = Vector2i(-1,0)
var cW = Color.GREEN
var E = Vector2i(1,0)
var cE = Color.RED
var cAny = Color.WHITE
var diagonal_dist = sqrt(2)

func col_to_str(col : Color) ->String:
	if(col == cN): return "cN(B)"
	if(col == cS): return "cS(Y)"
	if(col == cW): return "cW(G)"
	if(col == cE): return "cE(R)"
	if(col == cAny): return "cAny(W)"
	if(col == Color.BLACK): return "BLACK"
	return str(col)

func is_passable(sqr_col : Color, nbr_col : Color, dir : Vector2i) ->bool:
	if(sqr_col == cAny || nbr_col == cAny): return true
	if(dir == N): return (sqr_col == cN && nbr_col == cN)
	if(dir == S): return (sqr_col == cS && nbr_col == cS)
	if(dir == W): return (sqr_col == cW && nbr_col == cW)
	if(dir == E): return (sqr_col == cE && nbr_col == cE)
	return false
	
func visit_nbrs(vec : Vector2i, bfs_array : Array, grid : Image) -> void:
	var c_val = get_sqr_v(vec)
	var c_col = grid.get_pixelv(vec)
	var nbr_col = Color.BLACK
	
	print("->", vec, " C: ", col_to_str(c_col), " v: ", c_val)
	for dir in [N,S,W,E]:
		nbr_col = grid.get_pixelv(vec - dir)
		print("  <", vec-dir, "> P: ", is_passable(c_col, nbr_col, dir)," ", col_to_str(nbr_col), " | v:", get_sqr_v(vec + dir), " > ", c_val + 1.0)
		if(is_passable(c_col, nbr_col, dir) && get_sqr_v(vec - dir) > c_val + 1.0):
			set_sqr_v(vec - dir, c_val + 1.0)
			bfs_array.append(vec - dir)

func construct_destination_map(img : Image) -> void:
	for y in y_size:
		for x in x_size:
			if(img.get_pixel(x, y) == Color.BLACK):
				destmap_array.append(-1.0) # Impassable square
			else:
				destmap_array.append(INF) # Passable square
	var dest = find_random_destination()
	set_sqr_v(dest, 0.0)
	var bfs_array = []
	var new_bfs_array = []
	visit_nbrs(dest, bfs_array, img)
	
	while(bfs_array.size() != 0):
		print("len: ", bfs_array.size())
		new_bfs_array.clear()
		for vec in bfs_array:
			visit_nbrs(vec, new_bfs_array, img)
		bfs_array = new_bfs_array.duplicate()
		
	var largest_value = 0
	for x in x_size:
		for y in y_size:
			if(get_sqr(x,y) > largest_value && get_sqr(x,y) != INF):
				largest_value = get_sqr(x,y)
	var sqr_val = 0.0
	for x in x_size:
		for y in y_size:
			sqr_val = get_sqr(x, y)
			if(sqr_val == -1): img.set_pixel(x,y, Color.BLACK)
			elif(sqr_val == INF): img.set_pixel(x,y, Color.ORANGE)
			elif(sqr_val == 0): img.set_pixel(x,y, Color.LIME_GREEN)
			else: 
				var col = Color.WHITE
				col.g *= (sqr_val/largest_value)
				col.b = col.g
				img.set_pixel(x, y, col)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	x_size = _texture.get_width()
	y_size = _texture.get_height()
	
	var img = _texture.get_image()
	construct_destination_map(img)
	self.texture = ImageTexture.create_from_image(img)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

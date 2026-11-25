extends Sprite2D
@export var info_txt_box : Label
@export var base_texture: Texture2D
@export var test_car_tscn : Resource
@export var N_test_cars : int
@export var followed_car : int = -1
var viewed_map : int = 0

var x_size = 0
var y_size = 0

# Contains distances to destinations Array(Array(float))
var destination_maps : Array = []
@export var N_maps : int
# Contains lane directions Array(Vector2)
var direction_map = []

func get_dst(x: int, y: int, destmap_ID : int) -> float:
	var idx = (y * x_size) + x
	return destination_maps[destmap_ID][idx]

func get_dst_v(v : Vector2i, destmap_ID : int) -> float:
	var idx = (v.y * x_size) + v.x
	return destination_maps[destmap_ID][idx]

func set_dst(x: int, y: int, val: float, destmap_ID : int):
	var idx = (y * x_size) + x
	destination_maps[destmap_ID][idx] = val
	
func set_dst_v(v : Vector2i, val: float, destmap_ID : int):
	var idx = (v.y * x_size) + v.x
	destination_maps[destmap_ID][idx] = val
	
func get_dir(x: int, y: int) -> Vector2:
	var idx = (y * x_size) + x
	return direction_map[idx]

func get_dir_v(v : Vector2i) -> Vector2:
	var idx = (v.y * x_size) + v.x
	return direction_map[idx]

func set_dir(x: int, y: int, val: float):
	var idx = (y * x_size) + x
	direction_map[idx] = val
	
func set_dir_v(v : Vector2i, val: float):
	var idx = (v.y * x_size) + v.x
	direction_map[idx] = val

func vec_NAN(vec : Vector2) -> bool:
	return (is_nan(vec.x) || is_nan(vec.y))

func find_random_destination() -> Vector2i:
	var dest = Vector2i.ZERO
	while (true):
		dest.x = randi() % x_size
		dest.y = randi() % y_size
		if(!vec_NAN(get_dir(dest.x, dest.y))): 
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

var cNE = Color.from_rgba8(255,0,128,255)
var NE = N+E
var cNW = Color.from_rgba8(0,255,128,255)
var NW = N+W
var cSE = Color.from_rgba8(128,0,255,255)
var SE = S+E
var cSW = Color.from_rgba8(255,128,0,255)
var SW = S+W

var cAny = Color.WHITE

func are_directions_compatible(dir_A : Vector2, dir_B : Vector2) ->bool:
	var angle_AB = dir_A.angle_to(dir_B)
	return (abs(angle_AB) < 1.0) # approx. +/- 45 degrees
	

func col_to_str(col : Color) ->String:
	if(col == cN): return "cN(B)"
	if(col == cS): return "cS(Y)"
	if(col == cW): return "cW(G)"
	if(col == cE): return "cE(R)"
	if(col == cNE): return "cNE(P)"
	if(col == cNW): return "cNW(C)"
	if(col == cSE): return "cSE(M)"
	if(col == cSW): return "cSW(O)"
	if(col == cAny): return "cAny(W)"
	if(col == Color.BLACK): return "BLACK"
	return str(col)
	
func col_to_vec(col : Color) ->Vector2:
	if(col == cN): return Vector2(N)
	if(col == cS): return Vector2(S)
	if(col == cW): return Vector2(W)
	if(col == cE): return Vector2(E)
	if(col == cNE): return Vector2(NE)
	if(col == cNW): return Vector2(NW)
	if(col == cSE): return Vector2(SE)
	if(col == cSW): return Vector2(SW)
	if(col == Color.BLACK): return Vector2(NAN,NAN)
	if(col == cAny): return Vector2(0,0)
	else: push_error("Unknown color: ", col, " could not be converted to vector")
	return Vector2(NAN,NAN)

func is_passable_v(sqr_dir : Vector2, nbr_dir : Vector2, dir : Vector2) ->bool:
	if(vec_NAN(sqr_dir) || vec_NAN(nbr_dir)): return false
	return are_directions_compatible(sqr_dir, nbr_dir) && are_directions_compatible(sqr_dir, dir) && are_directions_compatible(dir, nbr_dir)

func within_bounds(pos : Vector2i) -> bool:
	return pos.x >= 0 && pos.x < x_size && pos.y >= 0 && pos.y < y_size

func visit_nbrs(pos : Vector2i, bfs_array : Array, destmap_ID : int) -> void:
	var c_val = get_dst_v(pos, destmap_ID) # Distance
	var c_dir = get_dir_v(pos) # Current lane direction
	var nbr_dir = Vector2(NAN, NAN)
	var nbr_val = INF
	
	#print("->", vec, " C: ", col_to_str(c_col), " v: ", c_val)
	for dir in [N,S,W,E,NE,NW,SE,SW]:
		if (!within_bounds(pos - dir)): continue
		
		nbr_dir = get_dir_v(pos - dir)
		nbr_val = get_dst_v(pos - dir, destmap_ID)
		#print("  <", vec-dir, "> P: ", is_passable(c_col, nbr_col, dir)," ", col_to_str(nbr_col), " | v:", get_sqr_v(vec + dir), " > ", c_val + 1.0)
		if(is_passable_v(c_dir, nbr_dir, dir) && nbr_val > c_val + dir.length()):
			set_dst_v(pos - dir, c_val + dir.length(), destmap_ID)
			bfs_array.append(pos - dir)

func construct_destination_maps() -> void:
	destination_maps.resize(N_maps)
	destination_maps.fill([]) # All destination-maps start from this template
	var dir_img = texture.get_image()
	
	var initial_destmap_setup : Array = []
	for y in y_size:
		for x in x_size:
			direction_map.append(col_to_vec(dir_img.get_pixel(x, y)))
			if(dir_img.get_pixel(x, y) == Color.BLACK):
				initial_destmap_setup.append(-1.0) # Impassable square
			else:
				initial_destmap_setup.append(INF) # Passable square
				
	
	for destmap_ID in range(0, N_maps):
		destination_maps[destmap_ID] = initial_destmap_setup.duplicate()
		var dest = find_random_destination()
		set_dst_v(dest, 0.0, destmap_ID)
		var bfs_array = []
		var new_bfs_array = []
		visit_nbrs(dest, bfs_array, destmap_ID)
	
		while(bfs_array.size() != 0):
			new_bfs_array.clear()
			for vec in bfs_array:
				visit_nbrs(vec, new_bfs_array, destmap_ID)
			bfs_array = new_bfs_array.duplicate()

func draw_destination_map(destmap_ID : int) ->void:
	var destmap_img = Image.create(x_size, y_size, false, Image.FORMAT_RGBA8)
	var largest_value = 0
	for x in x_size:
		for y in y_size:
			if(get_dst(x,y, destmap_ID) > largest_value && get_dst(x,y, destmap_ID) != INF):
				largest_value = get_dst(x,y, destmap_ID)
	var sqr_val = 0.0
	for x in x_size:
		for y in y_size:
			sqr_val = get_dst(x, y, destmap_ID)
			if(sqr_val == -1): destmap_img.set_pixel(x,y, Color.BLACK)
			elif(sqr_val == INF): destmap_img.set_pixel(x,y, Color.ORANGE)
			elif(sqr_val == 0): destmap_img.set_pixel(x,y, Color.LIME_GREEN)
			else: 
				var col : Color = Color(0.4, 0.4, 0.4, 1.0)
				col.r = 1.0-pow(sqr_val/largest_value, 0.5)
				col.g = 1.0-pow(abs((sqr_val-(largest_value/4))/(largest_value/4)), 0.5)
				col.b = 1.0-pow(abs((sqr_val-(largest_value/1.5))/(largest_value/1.5)), 0.5)
				destmap_img.set_pixel(x, y, col)
	self.texture = ImageTexture.create_from_image(destmap_img)


func find_next_sqr(car : Node2D) -> Vector2:
	var agent_sqr = Vector2i(floor(car.position.x), floor(car.position.y))
	var agent_lane_dir = get_dir_v(agent_sqr)
	var nbr_val : float = INF
	var nbr_lane_dir = Vector2(NAN, NAN)
	var lowest_val : float = INF
	var candidate_sqr : Vector2i = agent_sqr
	for dir in [N, S, W, E, NE, NW, SE, SW]:
		nbr_val = get_dst_v(agent_sqr + dir, car.destmap_ID)
		nbr_lane_dir = get_dir_v(agent_sqr + dir)
		if (nbr_val < lowest_val && nbr_val != -1 && is_passable_v(agent_lane_dir, nbr_lane_dir, dir)):
			lowest_val = nbr_val
			candidate_sqr = agent_sqr + dir
			
	if (lowest_val == 0.0):
		car.destmap_ID = randi_range(0, N_maps-1)
		if(car.follow_this_car):
			viewed_map = car.destmap_ID
			draw_destination_map(viewed_map)
	if (lowest_val == INF):
		printerr("WARNING: ", car.name, " -> destination: ", car.destmap_ID, " cannot find a valid route.")
		car.destmap_ID = randi_range(0, N_maps-1)
		
	return Vector2(candidate_sqr.x + 0.5, candidate_sqr.y + 0.5)
	
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	x_size = base_texture.get_width()
	y_size = base_texture.get_height()
	
	self.position = Vector2(x_size/2.0, y_size/2.0)
	
	construct_destination_maps()
	draw_destination_map(viewed_map)
	
	print(get_dst(1,1, 0))
	print(get_dst(1,1, 1))
	print(get_dst(1,1, 2))
	print(get_dst(1,1, 3))
	
	for n in range(0, N_test_cars):
		var car : Node2D = test_car_tscn.instantiate()
		car.position = find_random_destination()
		car.destmap_ID = randi_range(0, N_maps-1)
		car.traffic_system = self
		car.name = str("Car(", n, ")")
		if(n == followed_car): car.follow_this_car = true
		
		add_sibling.call_deferred(car)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	info_txt_box.text = str(roundi(delta*1000), "ms\nDestination-Map: ", viewed_map)
	
func _input(event):
	if(event.is_action_pressed("ui_up") && viewed_map < N_maps-1):
		viewed_map += 1
		draw_destination_map(viewed_map)
		print("Showing destination-map: ", viewed_map)
	if(event.is_action_pressed("ui_down") && viewed_map > 0):
		viewed_map -= 1
		draw_destination_map(viewed_map)
		print("Showing destination-map: ", viewed_map)

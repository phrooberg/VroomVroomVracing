extends Node2D

@export var traffic_system : Node
var destmap_ID = 0
var local_dest : Vector2 = Vector2.ZERO
var speed : float = 8.0 + 12.0*randf()
var debug : bool = false
var follow_this_car : bool = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.modulate = Color(randf(), randf(), randf(), 1.0)
	local_dest = traffic_system.find_next_sqr(self)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	var distance = local_dest.distance_to(self.position)
	var travel_dir : Vector2 = (self.position - local_dest)
	travel_dir = travel_dir.normalized()
	
	if(debug): print("Pos: ", self.position, "Dest: ", local_dest, "Dist: ", distance)
	
	self.position -= travel_dir * delta * speed
	self.look_at(local_dest)
	
	if(distance < 0.25):
		local_dest = traffic_system.find_next_sqr(self)
		

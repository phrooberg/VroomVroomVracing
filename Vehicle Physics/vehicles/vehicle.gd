extends VehicleBody3D

@export var STEER_SPEED = 2.1
@export var STEER_LIMIT = 0.5
@export var BRAKE_STRENGTH = 20.0

@export var engine_force_value := 3000.0

@export var front_left_wheel: VehicleWheel3D
@export var front_right_wheel: VehicleWheel3D
@export var rear_left_wheel: VehicleWheel3D
@export var rear_right_wheel: VehicleWheel3D

@export var base_front_wheel_friction: float = 2.2
@export var base_rear_wheel_friction: float = 2.0
@export var speed: float = 0.0

var previous_speed := linear_velocity.length()
var _steer_target := 0.0
var slip_ratio = 1.0
var slip_angle = 0.0

func _physics_process(delta: float) -> void:
	_steer_target = Input.get_axis(&"turn_right", &"turn_left")
	_steer_target *= STEER_LIMIT
	speed = linear_velocity.length()
	brake = 5
	engine_force = 0.0
	
	if slip_ratio < 1.0:
		slip_ratio += 0.03
	else:
		slip_ratio = 1.0
		
	if Input.is_action_pressed(&"accelerate"):
		engine_force = engine_force_value * sin(clampf(speed / 30, PI/3, PI))
		#print(speed)
		#print(engine_force)
		slip_ratio = 1.0 - clampf(engine_force / 1200 / speed, 0.0, 1.0)
		
	if Input.is_action_pressed(&"reverse"):
		if speed > 8.0:
			brake = 30
			slip_ratio = 1.0 - clampf(speed / 200, 0.0, 1.0)
			engine_force = 0.0
		else:
			engine_force = -engine_force_value

	steering = move_toward(steering, _steer_target, STEER_SPEED * clamp(speed / 10, 1, 2) * delta)
	previous_speed = linear_velocity.length()
	
	var wheel_direction = -front_left_wheel.global_transform.basis.x
	slip_angle = abs(wheel_direction.dot(linear_velocity.normalized()))
	#print(slip_angle)


	for wheel in [front_left_wheel, front_right_wheel]:
		wheel.wheel_friction_slip = base_front_wheel_friction - (slip_angle * clampf(speed / 50, 0.0, 3.0))
		
	for wheel in [rear_left_wheel, rear_right_wheel]:
		wheel.wheel_friction_slip = (base_rear_wheel_friction * slip_ratio) - (slip_angle / 20 * clampf(speed, 0.0, 3.0))

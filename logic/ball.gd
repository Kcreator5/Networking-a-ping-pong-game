extends Area2D


const DEFAULT_SPEED = 100.0
const SERVE_HELD = 0
const SERVE_TOSSED = 1
const SERVE_IN_PLAY = 2

@export_range(1.0, 10.0, 0.1) var height_indicator = 1.0
@export var bounce_enabled = true
@export var ball_gravity = 32.0
@export var serve_gravity_scale = 0.65
@export var serve_toss_velocity = 10.0
@export var serve_landing_bounce = 0.35
@export var serve_paddle_collision_delay = 0.5
@export var serve_collision_delay_tint = Color(0.7, 0.8, 1.0, 0.75)
@export var ball_bounciness = 0.90
@export var min_table_bounce_velocity = 3.5
@export var table_bounds = Rect2(38, 132, 284, 536)
@export var table_surface_height = 1.0
@export var floor_surface_height = -1.0
@export var despawn_on_floor = true
@export var respawn_delay = 0.6
@export var serving_paddle_path: NodePath = NodePath("../Right")
@export var serve_follow_distance = 30.0
@export var height_hit_impulse = 4.0
@export var height_hit_impulse_from_paddle = 4.0
@export var max_visual_height = 28.0
@export var max_visual_scale = 1.8
@export var speed_increase_per_second = 0.2
@export var min_speed = 50.0
@export var max_speed = 280.0
@export var hit_strength_for_max = 200.0
@export var min_hit_speed_boost = 0.0
@export var max_hit_speed_boost = 85.0
@export var backward_hit_slowdown_scale = 0.75
@export var paddle_velocity_influence = 1.0
@export var paddle_vertical_influence = 0.45
@export var min_bounce_x_strength = 0.30
@export var score_on_floor_landing = true

var _speed = DEFAULT_SPEED
var direction = Vector2.LEFT
var velocity = Vector2.LEFT * DEFAULT_SPEED
var height_velocity = 0.0
var spin_velocity = 0.0
var _respawning = false
var _serve_state = SERVE_HELD
var _serve_collision_delay_remaining = 0.0
var _base_sprite_modulate = Color.WHITE
var table_bounces_left = 0
var table_bounces_right = 0
var last_table_bounce_side = ""
var _serving_paddle

@onready var _sprite = $Sprite2D
@onready var _shadow = $Shadow
@onready var _initial_pos = position
@onready var _base_sprite_position = _sprite.position
@onready var _base_sprite_scale = _sprite.scale
@onready var _base_shadow_scale = _shadow.scale


func _ready():
	_serving_paddle = get_node_or_null(serving_paddle_path)
	_base_sprite_modulate = _sprite.modulate
	reset()


func _process(delta):
	_update_serve_collision_delay(delta)

	if _serve_state == SERVE_HELD:
		_follow_serving_paddle()
		_update_fake_height_visual()
		return

	if _serve_state == SERVE_IN_PLAY:
		_speed = min(_speed + delta * speed_increase_per_second, max_speed)
		velocity = velocity.normalized() * _speed
		position += velocity * delta
		direction = velocity.normalized()

	_update_height_physics(delta)
	_update_fake_height_visual()


func reset():
	direction = Vector2.LEFT
	velocity = Vector2.ZERO
	position = _initial_pos
	_speed = DEFAULT_SPEED
	height_indicator = table_surface_height
	height_velocity = 0.0
	spin_velocity = 0.0
	_serve_collision_delay_remaining = 0.0
	_update_collision_delay_visual()
	visible = true
	set_process(true)
	monitoring = true
	_respawning = false
	_serve_state = SERVE_HELD
	_reset_table_bounce_tracking()
	_follow_serving_paddle()


func is_serving_for(paddle):
	return _serve_state == SERVE_HELD and paddle == _serving_paddle


func set_serving_paddle(paddle):
	_serving_paddle = paddle
	serving_paddle_path = get_path_to(paddle)
	if _serve_state == SERVE_HELD:
		_follow_serving_paddle()


func toss_serve_from(paddle):
	if not is_serving_for(paddle):
		return false

	_serve_state = SERVE_TOSSED
	velocity = Vector2.ZERO
	_speed = 0.0
	direction = Vector2.ZERO
	height_indicator = max(height_indicator, table_surface_height)
	height_velocity = serve_toss_velocity
	_serve_collision_delay_remaining = serve_paddle_collision_delay
	_update_collision_delay_visual()
	return true


func bounce_off_horizontal(surface_direction):
	if _serve_state != SERVE_IN_PLAY:
		return

	velocity.y = abs(velocity.y) * surface_direction
	if is_zero_approx(velocity.y):
		velocity.y = DEFAULT_SPEED * 0.35 * surface_direction
	velocity = velocity.normalized() * _speed
	direction = velocity.normalized()


func hit_paddle(paddle, exit_direction):
	if _serve_collision_delay_remaining > 0.0:
		return false

	var exit_vector = Vector2(exit_direction, 0)
	if paddle.has_method("get_exit_vector"):
		exit_vector = paddle.get_exit_vector().normalized()
	if exit_vector == Vector2.ZERO:
		exit_vector = Vector2.RIGHT
	var tangent_vector = Vector2(-exit_vector.y, exit_vector.x)

	_reset_table_bounce_tracking()
	var incoming_velocity = velocity
	if _serve_state == SERVE_TOSSED:
		incoming_velocity = -exit_vector * DEFAULT_SPEED
		_speed = DEFAULT_SPEED
		_serve_state = SERVE_IN_PLAY

	var forward_speed = max(abs(incoming_velocity.dot(exit_vector)), DEFAULT_SPEED)
	var reflected_velocity = exit_vector * forward_speed

	var paddle_velocity = Vector2.ZERO
	var hit_strength = 0.0
	var forward_hit_strength = 0.0
	if paddle.has_method("get_paddle_velocity"):
		paddle_velocity = paddle.get_paddle_velocity()
		hit_strength = clamp(paddle_velocity.length() / hit_strength_for_max, 0.0, 1.0)
		forward_hit_strength = clamp(paddle_velocity.dot(exit_vector) / hit_strength_for_max, -1.0, 1.0)
		reflected_velocity += exit_vector * paddle_velocity.dot(exit_vector) * paddle_velocity_influence
		reflected_velocity += tangent_vector * paddle_velocity.dot(tangent_vector) * paddle_vertical_influence

	if reflected_velocity.dot(exit_vector) <= 0.0:
		reflected_velocity += exit_vector * (abs(reflected_velocity.dot(exit_vector)) + DEFAULT_SPEED * min_bounce_x_strength)

	var normalized_hit = reflected_velocity.normalized()
	if abs(normalized_hit.dot(exit_vector)) < min_bounce_x_strength:
		reflected_velocity += exit_vector * max(_speed, DEFAULT_SPEED) * min_bounce_x_strength

	var speed_change = 0.0
	if forward_hit_strength > 0.0:
		speed_change = lerp(min_hit_speed_boost, max_hit_speed_boost, forward_hit_strength)
	elif forward_hit_strength < 0.0:
		speed_change = forward_hit_strength * max_hit_speed_boost * backward_hit_slowdown_scale

	_speed = clamp(max(_speed, DEFAULT_SPEED) + speed_change, min_speed, max_speed)
	_apply_height_hit(paddle, hit_strength)

	velocity = reflected_velocity.normalized() * _speed
	direction = velocity.normalized()
	_serve_state = SERVE_IN_PLAY
	return true


func _reflect_velocity(incoming_velocity, normal):
	var safe_normal = normal.normalized()
	if incoming_velocity.dot(safe_normal) > 0:
		safe_normal = -safe_normal
	return incoming_velocity - 2.0 * incoming_velocity.dot(safe_normal) * safe_normal


func _apply_height_hit(paddle, hit_strength):
	var height_direction = 1.0
	if paddle.has_method("get_paddle_height_direction"):
		height_direction = paddle.get_paddle_height_direction()

	var impulse = height_hit_impulse + height_hit_impulse_from_paddle * hit_strength
	height_velocity = impulse * height_direction


func _update_height_physics(delta):
	if not bounce_enabled:
		return

	var surface_height = _get_surface_height()
	var gravity = ball_gravity
	if _serve_state == SERVE_TOSSED:
		gravity *= serve_gravity_scale

	height_indicator += height_velocity * delta
	height_velocity -= gravity * delta

	if height_indicator <= surface_height:
		height_indicator = surface_height
		if _serve_state == SERVE_TOSSED:
			if is_equal_approx(surface_height, floor_surface_height) and despawn_on_floor:
				_score_floor_landing()
				_despawn_on_floor()
				return
			if height_velocity < 0.0:
				_record_table_bounce()
				height_velocity = abs(height_velocity) * serve_landing_bounce
			return

		if is_equal_approx(surface_height, floor_surface_height) and despawn_on_floor:
			_score_floor_landing()
			_despawn_on_floor()
			return

		if height_velocity < 0.0:
			_record_table_bounce()
			height_velocity = max(abs(height_velocity) * ball_bounciness, min_table_bounce_velocity)

	if height_indicator >= 10.0:
		height_indicator = 10.0
		if height_velocity > 0.0:
			height_velocity = 0.0


func _update_serve_collision_delay(delta):
	if _serve_collision_delay_remaining <= 0.0:
		return

	_serve_collision_delay_remaining = max(_serve_collision_delay_remaining - delta, 0.0)
	_update_collision_delay_visual()


func _update_collision_delay_visual():
	if _sprite == null:
		return

	if _serve_collision_delay_remaining <= 0.0:
		_sprite.modulate = _base_sprite_modulate
		return

	_sprite.modulate = serve_collision_delay_tint

func _record_table_bounce():
	var side = _get_position_side()
	last_table_bounce_side = side
	if side == "left":
		table_bounces_left += 1
	else:
		table_bounces_right += 1


func _reset_table_bounce_tracking():
	table_bounces_left = 0
	table_bounces_right = 0
	last_table_bounce_side = ""


func _score_floor_landing():
	if not score_on_floor_landing:
		return

	var scoreboard = get_parent().get_node_or_null("Scoreboard")
	if scoreboard == null:
		return

	var score_label_name = "LeftScore"
	if _get_position_side() == "left":
		score_label_name = "RightScore"

	var score_label = scoreboard.get_node_or_null(score_label_name)
	if score_label == null:
		return

	score_label.text = str(int(score_label.text) + 1)


func _get_position_side():
	if position.y < table_bounds.position.y + table_bounds.size.y * 0.5:
		return "left"
	return "right"

func _get_surface_height():
	if table_bounds.has_point(position):
		return table_surface_height
	return floor_surface_height


func _despawn_on_floor():
	if _respawning:
		return

	_respawning = true
	visible = false
	set_process(false)
	monitoring = false
	await get_tree().create_timer(respawn_delay).timeout
	reset()


func _follow_serving_paddle():
	if _serving_paddle == null:
		return

	var side = -1.0
	if String(_serving_paddle.name).to_lower() == "left":
		side = 1.0
	position = _serving_paddle.position + Vector2(0, serve_follow_distance * side)


func _update_fake_height_visual():
	height_indicator = clamp(height_indicator, floor_surface_height, 10.0)

	var height_percent = height_indicator / 10.0
	_sprite.position = _base_sprite_position + Vector2(0, -max_visual_height * height_percent)
	_sprite.scale = _base_sprite_scale * lerp(1.0, max_visual_scale, height_percent)

	_shadow.position = _base_sprite_position
	_shadow.scale = _base_shadow_scale * lerp(1.15, 0.55, height_percent)
	_shadow.modulate = Color(0, 0, 0, lerp(0.35, 0.72, height_percent))

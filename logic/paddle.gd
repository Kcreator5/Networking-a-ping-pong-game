extends Area2D


const MOVE_SPEED = 300

@export var True_mouse_follow = true
@export var follow_mouse = false
@export var follow_mouse_horizontal = false
@export var mouse_follow_speed = 700.0
@export var mouse_acceleration = 2200.0
@export var mouse_deceleration = 2000.0
@export var mouse_snap_distance = 3.0
@export var mouse_min_x = 16.0
@export var mouse_max_x = -1.0
@export var mouse_min_y = 16.0
@export var mouse_max_y = -1.0
@export var keyboard_control = false
@export var keyboard_allow_horizontal = true
@export var keyboard_min_x = 16.0
@export var keyboard_max_x = -1.0
@export var keyboard_min_y = 16.0
@export var keyboard_max_y = -1.0
@export var keyboard_topspin_key = KEY_SPACE
@export var keyboard_backspin_key = KEY_Q
@export var rotate_with_mouse_buttons = false
@export var rotation_speed_degrees = 90.0
@export var scroll_rotation_step_degrees = 4.0
@export var min_rotation_degrees = -45.0
@export var max_rotation_degrees = 45.0
@export var hit_cooldown_duration = 1.0
@export var cooldown_tint = Color(0.45, 0.45, 0.45, 1.0)
@export var cycle_sprite_frames = false
@export var sprite_frame_count = 1
@export var sprite_frame_index = 0
@export var first_red_sprite_frame = 5
@export var default_sprite_frame = 4
@export var spin_animation_fps = 20.0
@export var use_mouse_spin_controls = false
@export var use_keyboard_spin_controls = false
@export var use_debug_frame_keys = false
@export var touch_control_enabled = true
@export var touch_velocity_multiplier = 1.0
@export var touch_velocity_falloff = 12.0

var paddle_velocity = Vector2.ZERO
var paddle_speed = 0.0
var paddle_rotation_degrees = 0.0
var paddle_angular_velocity = 0.0
var hit_cooldown_remaining = 0.0
var touch_control_active = false
var _last_sampled_position = Vector2.ZERO
var _recent_touch_velocity = Vector2.ZERO

var _ball_dir
var _exit_vector = Vector2.RIGHT
var _up
var _down
var _base_sprite_modulate = Color.WHITE
var _spin_animation_frames = []
var _spin_animation_index = 0
var _spin_animation_time = 0.0
var _last_spin_height_direction = 1.0

@onready var _sprite = get_node_or_null("Sprite2D") as Sprite2D
@onready var _screen_size_x = get_viewport_rect().size.x
@onready var _screen_size_y = get_viewport_rect().size.y


func _ready():
	var n = String(name).to_lower()
	_up = n + "_move_up"
	_down = n + "_move_down"
	if n == "left":
		_ball_dir = 1
		_exit_vector = Vector2.DOWN
	else:
		_ball_dir = -1
		_exit_vector = Vector2.UP
	if _sprite != null:
		_base_sprite_modulate = _sprite.modulate
	_apply_sprite_frame()


func _input(event):
	if not cycle_sprite_frames:
		return

	if event is InputEventMouseButton and event.pressed and use_mouse_spin_controls:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_serve_angle(-scroll_rotation_step_degrees)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_serve_angle(scroll_rotation_step_degrees)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_start_topspin_animation()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_start_backspin_animation()

	if event is InputEventKey and event.pressed and not event.echo and use_keyboard_spin_controls:
		if event.keycode == keyboard_topspin_key:
			_start_topspin_animation()
		elif event.keycode == keyboard_backspin_key:
			_start_backspin_animation()

	if event is InputEventKey and event.pressed and not event.echo and use_debug_frame_keys:
		if event.keycode == KEY_O:
			_change_sprite_frame(1)
		elif event.keycode == KEY_K:
			_change_sprite_frame(-1)


func _process(delta):
	_update_rotation(delta)
	_update_hit_cooldown(delta)
	_update_spin_animation(delta)

	if touch_control_active:
		_sample_position_velocity(delta)
		return

	_decay_recent_touch_velocity(delta)

	if follow_mouse:
		var mouse_position = get_global_mouse_position()
		var target_position = position
		target_position.y = clamp(mouse_position.y, _get_min_y(), _get_max_y())

		if follow_mouse_horizontal:
			var max_x = mouse_max_x
			if max_x < 0:
				max_x = _screen_size_x - 16
			target_position.x = clamp(mouse_position.x, mouse_min_x, max_x)

		if True_mouse_follow:
			if delta > 0.0:
				paddle_velocity = (target_position - position) / delta
			else:
				paddle_velocity = Vector2.ZERO
			position = target_position
			paddle_speed = paddle_velocity.length()
			return

		_move_with_velocity(target_position, delta)
		return

	if keyboard_control:
		_move_with_keyboard(delta)
		return

	# Move up and down based on input.
	var input = Input.get_action_strength(_down) - Input.get_action_strength(_up)
	paddle_velocity = Vector2(0, input * MOVE_SPEED)
	paddle_speed = abs(paddle_velocity.y)
	position.y = clamp(position.y + paddle_velocity.y * delta, _get_min_y(), _get_max_y())


func _on_area_entered(area):
	if area.name == "Ball":
		if hit_cooldown_remaining > 0.0:
			return

		if area.hit_paddle(self, _ball_dir):
			hit_cooldown_remaining = hit_cooldown_duration
			_update_cooldown_visual()


func get_exit_vector():
	return _exit_vector


func get_paddle_velocity():
	if _recent_touch_velocity.length() > paddle_velocity.length():
		return _recent_touch_velocity
	return paddle_velocity


func get_paddle_rotation_degrees():
	return paddle_rotation_degrees


func get_paddle_angular_velocity():
	return paddle_angular_velocity


func get_paddle_height_direction():
	return _last_spin_height_direction


func can_hit_ball():
	return hit_cooldown_remaining <= 0.0


func get_hit_cooldown_percent():
	if hit_cooldown_duration <= 0.0:
		return 0.0
	return hit_cooldown_remaining / hit_cooldown_duration


func _update_hit_cooldown(delta):
	if hit_cooldown_remaining <= 0.0:
		return

	hit_cooldown_remaining = max(hit_cooldown_remaining - delta, 0.0)
	_update_cooldown_visual()


func _update_cooldown_visual():
	if _sprite == null:
		return

	if hit_cooldown_remaining <= 0.0:
		_sprite.modulate = _base_sprite_modulate
		return

	var cooldown_percent = get_hit_cooldown_percent()
	_sprite.modulate = _base_sprite_modulate.lerp(cooldown_tint, cooldown_percent)


func _update_rotation(delta):
	rotation_degrees = 0.0
	paddle_rotation_degrees = 0.0
	paddle_angular_velocity = 0.0


func _change_serve_angle(delta_degrees):
	var previous_rotation = rotation_degrees
	rotation_degrees = clamp(
		rotation_degrees + delta_degrees,
		min_rotation_degrees,
		max_rotation_degrees
	)
	paddle_rotation_degrees = rotation_degrees
	paddle_angular_velocity = 0.0


func _start_topspin_animation():
	if _try_toss_served_ball():
		return

	_last_spin_height_direction = 1.0
	_start_spin_animation([default_sprite_frame, 5, 6, 7, 8, 8, 7, 6, 5, default_sprite_frame])


func _start_backspin_animation():
	if _try_toss_served_ball():
		return

	_last_spin_height_direction = -1.0
	_start_spin_animation([default_sprite_frame, 3, 2, 1, 0, 0, 1, 2, 3, default_sprite_frame])


func _try_toss_served_ball():
	var ball = get_parent().get_node_or_null("Ball")
	if ball != null and ball.has_method("toss_serve_from"):
		return ball.toss_serve_from(self)
	return false


func _start_spin_animation(frames):
	_spin_animation_frames = frames
	_spin_animation_index = 0
	_spin_animation_time = 0.0
	_set_sprite_frame(_spin_animation_frames[_spin_animation_index])


func _update_spin_animation(delta):
	if _spin_animation_frames.is_empty():
		return

	_spin_animation_time += delta
	var seconds_per_frame = 1.0 / spin_animation_fps
	while _spin_animation_time >= seconds_per_frame and not _spin_animation_frames.is_empty():
		_spin_animation_time -= seconds_per_frame
		_spin_animation_index += 1
		if _spin_animation_index >= _spin_animation_frames.size():
			_spin_animation_frames = []
			_set_sprite_frame(default_sprite_frame)
			return

		_set_sprite_frame(_spin_animation_frames[_spin_animation_index])


func start_touch_control(global_position, delta = 0.0):
	if not touch_control_enabled:
		return

	touch_control_active = true
	_last_sampled_position = position
	_teleport_to_touch(global_position, delta)
	_sample_position_velocity(max(delta, get_process_delta_time()))


func update_touch_control(global_position, delta = 0.0):
	if not touch_control_enabled or not touch_control_active:
		return

	_teleport_to_touch(global_position, delta)


func end_touch_control():
	touch_control_active = false
	paddle_velocity = _recent_touch_velocity
	paddle_speed = paddle_velocity.length()


func _teleport_to_touch(global_position, delta):
	var target_position = position
	target_position.y = clamp(global_position.y, _get_min_y(), _get_max_y())

	var min_x = keyboard_min_x
	var max_x = keyboard_max_x
	if follow_mouse:
		min_x = mouse_min_x
		max_x = mouse_max_x
	if max_x < 0:
		max_x = _screen_size_x - 16
	target_position.x = clamp(global_position.x, min_x, max_x)

	if delta > 0.0:
		paddle_velocity = (target_position - position) / delta
	else:
		paddle_velocity = Vector2.ZERO
	position = target_position
	paddle_speed = paddle_velocity.length()

func _sample_position_velocity(delta):
	if delta <= 0.0:
		return

	var measured_velocity = (position - _last_sampled_position) / delta * touch_velocity_multiplier
	if measured_velocity.length() > 0.01:
		paddle_velocity = measured_velocity
		_recent_touch_velocity = measured_velocity
		paddle_speed = paddle_velocity.length()
	_last_sampled_position = position


func _decay_recent_touch_velocity(delta):
	_recent_touch_velocity = _recent_touch_velocity.move_toward(Vector2.ZERO, touch_velocity_falloff * max(_recent_touch_velocity.length(), 1.0) * delta)

func _move_with_keyboard(delta):
	var input = Vector2.ZERO
	if keyboard_allow_horizontal:
		input.x = int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
	input.y = int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W))

	if input.length() > 1.0:
		input = input.normalized()

	paddle_velocity = input * MOVE_SPEED
	paddle_speed = paddle_velocity.length()
	position += paddle_velocity * delta

	var max_x = keyboard_max_x
	if max_x < 0:
		max_x = _screen_size_x - 16
	position.x = clamp(position.x, keyboard_min_x, max_x)
	position.y = clamp(position.y, _get_min_y(), _get_max_y())


func _move_with_velocity(target_position, delta):
	var to_target = target_position - position
	var desired_velocity = Vector2.ZERO

	if to_target.length() <= mouse_snap_distance:
		position = target_position
		paddle_velocity = Vector2.ZERO
		paddle_speed = 0.0
		return

	if to_target.length() > 0.0:
		desired_velocity = to_target.normalized() * mouse_follow_speed

	var acceleration = mouse_deceleration
	if desired_velocity.length() > paddle_velocity.length():
		acceleration = mouse_acceleration

	paddle_velocity = paddle_velocity.move_toward(desired_velocity, acceleration * delta)
	var next_position = position + paddle_velocity * delta
	if (target_position - next_position).dot(to_target) <= 0.0:
		position = target_position
		paddle_velocity = Vector2.ZERO
		paddle_speed = 0.0
		return

	position = next_position

	var max_x = mouse_max_x
	if max_x < 0:
		max_x = _screen_size_x - 16
	position.x = clamp(position.x, mouse_min_x, max_x)
	position.y = clamp(position.y, _get_min_y(), _get_max_y())

	if is_equal_approx(position.x, mouse_min_x) or is_equal_approx(position.x, max_x):
		paddle_velocity.x = 0
	if is_equal_approx(position.y, _get_min_y()) or is_equal_approx(position.y, _get_max_y()):
		paddle_velocity.y = 0

	paddle_speed = paddle_velocity.length()


func _get_min_y():
	if follow_mouse:
		return mouse_min_y
	return keyboard_min_y


func _get_max_y():
	var max_y = keyboard_max_y
	if follow_mouse:
		max_y = mouse_max_y
	if max_y < 0:
		max_y = _screen_size_y - 16
	return max_y

func _change_sprite_frame(direction):
	var max_frame_index = max(sprite_frame_count - 1, 0)
	var next_frame_index = clamp(sprite_frame_index + direction, 0, max_frame_index)
	if next_frame_index == sprite_frame_index:
		return

	_set_sprite_frame(next_frame_index)


func _apply_sprite_frame():
	if not cycle_sprite_frames or _sprite == null or _sprite.texture == null:
		return

	var safe_frame_count = max(sprite_frame_count, 1)
	var texture_size = _sprite.texture.get_size()
	var frame_width = texture_size.x / safe_frame_count
	var clamped_frame = clamp(sprite_frame_index, 0, safe_frame_count - 1)
	sprite_frame_index = clamped_frame
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(frame_width * clamped_frame, 0, frame_width, texture_size.y)


func _set_sprite_frame(frame_index):
	sprite_frame_index = clamp(frame_index, 0, max(sprite_frame_count - 1, 0))
	_apply_sprite_frame()

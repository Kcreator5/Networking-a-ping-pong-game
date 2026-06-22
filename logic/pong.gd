extends Node2D


const NETWORK_SYNC_RATE = 1.0 / 30.0
const TAP_SERVE_MAX_DURATION = 0.5

var _mode = "one_player"
var _selected_side = "right"
var _network_role = "offline"
var _sync_time = 0.0
var _network_manager
var _touch_paddle_by_index = {}
var _touch_started_at_by_index = {}
var _touch_last_position_by_index = {}
var _touch_last_time_by_index = {}
var _mouse_touch_index = -100
var _serving_side = "right"
var _serves_taken_by_current_server = 0


func _ready():
	_network_manager = get_node_or_null("/root/NetworkManager")
	_apply_initial_server()
	_apply_game_mode()
	_connect_network_status()
	_connect_game_sync()


func _process(delta):
	_update_network_sync(delta)


func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		var network_manager = get_node_or_null("/root/NetworkManager")
		if network_manager != null:
			network_manager.close_connection()
		get_tree().change_scene_to_file("res://title_screen.tscn")
		return

	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse_touch_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_touch_drag(event)


func _handle_screen_touch(event):
	if event.pressed:
		var side = _get_touch_start_side(event.position)
		if not _can_touch_control_side(side):
			return

		var paddle = _get_paddle_for_side(side)
		if paddle == null:
			return

		var touch_position = _screen_to_world(event.position)
		var now = _get_now_seconds()
		_touch_paddle_by_index[event.index] = paddle
		_touch_started_at_by_index[event.index] = now
		_touch_last_time_by_index[event.index] = now
		_touch_last_position_by_index[event.index] = touch_position
		paddle.start_touch_control(touch_position)
		get_viewport().set_input_as_handled()
		return

	var paddle = _touch_paddle_by_index.get(event.index)
	var touch_duration = _get_touch_duration(event.index)
	if paddle != null:
		_try_tap_serve(paddle, touch_duration)
		if paddle.has_method("end_touch_control"):
			paddle.end_touch_control()
	_touch_paddle_by_index.erase(event.index)
	_touch_started_at_by_index.erase(event.index)
	_touch_last_position_by_index.erase(event.index)
	_touch_last_time_by_index.erase(event.index)
	get_viewport().set_input_as_handled()


func _handle_screen_drag(event):
	var paddle = _touch_paddle_by_index.get(event.index)
	if paddle == null:
		return

	var touch_position = _screen_to_world(event.position)
	var delta = _get_touch_delta_time(event.index)
	paddle.update_touch_control(touch_position, delta)
	_touch_last_position_by_index[event.index] = touch_position
	_touch_last_time_by_index[event.index] = _get_now_seconds()
	get_viewport().set_input_as_handled()


func _handle_mouse_touch_button(event):
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		var side = _get_touch_start_side(event.position)
		if not _can_touch_control_side(side):
			return

		var paddle = _get_paddle_for_side(side)
		if paddle == null:
			return

		var touch_position = _screen_to_world(event.position)
		var now = _get_now_seconds()
		_touch_paddle_by_index[_mouse_touch_index] = paddle
		_touch_started_at_by_index[_mouse_touch_index] = now
		_touch_last_time_by_index[_mouse_touch_index] = now
		_touch_last_position_by_index[_mouse_touch_index] = touch_position
		paddle.start_touch_control(touch_position)
		get_viewport().set_input_as_handled()
		return

	var paddle = _touch_paddle_by_index.get(_mouse_touch_index)
	var touch_duration = _get_touch_duration(_mouse_touch_index)
	if paddle != null:
		_try_tap_serve(paddle, touch_duration)
		if paddle.has_method("end_touch_control"):
			paddle.end_touch_control()
	_touch_paddle_by_index.erase(_mouse_touch_index)
	_touch_started_at_by_index.erase(_mouse_touch_index)
	_touch_last_position_by_index.erase(_mouse_touch_index)
	_touch_last_time_by_index.erase(_mouse_touch_index)
	get_viewport().set_input_as_handled()


func _handle_mouse_touch_drag(event):
	if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return

	var paddle = _touch_paddle_by_index.get(_mouse_touch_index)
	if paddle == null:
		return

	var touch_position = _screen_to_world(event.position)
	var delta = _get_touch_delta_time(_mouse_touch_index)
	paddle.update_touch_control(touch_position, delta)
	_touch_last_position_by_index[_mouse_touch_index] = touch_position
	_touch_last_time_by_index[_mouse_touch_index] = _get_now_seconds()
	get_viewport().set_input_as_handled()

func _get_now_seconds():
	return Time.get_ticks_msec() / 1000.0


func _get_touch_duration(index):
	return _get_now_seconds() - float(_touch_started_at_by_index.get(index, _get_now_seconds()))


func _get_touch_delta_time(index):
	var now = _get_now_seconds()
	var last_time = float(_touch_last_time_by_index.get(index, now))
	return max(now - last_time, 0.001)


func _try_tap_serve(paddle, touch_duration):
	if touch_duration > TAP_SERVE_MAX_DURATION:
		return false

	var ball = $Ball
	if ball == null or not ball.has_method("toss_serve_from"):
		return false
	if not ball.toss_serve_from(paddle):
		return false

	_register_completed_serve()
	return true


func _register_completed_serve():
	_serves_taken_by_current_server += 1
	if _serves_taken_by_current_server < 2:
		return

	_serves_taken_by_current_server = 0
	if _serving_side == "left":
		_serving_side = "right"
	else:
		_serving_side = "left"
	_apply_serving_side()


func _apply_initial_server():
	_serving_side = "right"
	_serves_taken_by_current_server = 0
	_apply_serving_side()


func _apply_serving_side():
	if not is_inside_tree() or not has_node("Ball"):
		return

	var ball = $Ball
	var paddle = _get_paddle_for_side(_serving_side)
	if paddle != null and ball.has_method("set_serving_paddle"):
		ball.set_serving_paddle(paddle)

func _get_touch_start_side(screen_position):
	if screen_position.y < get_viewport_rect().size.y * 0.5:
		return "left"
	return "right"


func _get_paddle_for_side(side):
	if side == "left":
		return $Left
	return $Right


func _can_touch_control_side(side):
	if _mode == "one_player":
		return true
	return side == _selected_side


func _screen_to_world(screen_position):
	return get_canvas_transform().affine_inverse() * screen_position

func _apply_game_mode():
	var left = $Left
	var right = $Right
	_mode = "one_player"
	_selected_side = "right"
	_network_role = "offline"

	if has_node("/root/GameMode"):
		_mode = GameMode.mode
		_selected_side = GameMode.selected_side
		_network_role = GameMode.network_role

	_disable_player_control(left)
	_disable_player_control(right)

	if _mode == "one_player":
		_enable_right_mouse_control(right)
		_enable_left_keyboard_control(left)
		_set_client_ball_sync(false)
	elif _selected_side == "left":
		_enable_left_keyboard_control(left)
		_set_client_ball_sync(true)
	else:
		_enable_right_mouse_control(right)
		_set_client_ball_sync(false)


func _disable_player_control(paddle):
	paddle.follow_mouse = false
	paddle.True_mouse_follow = false
	paddle.keyboard_control = false
	paddle.use_mouse_spin_controls = false
	paddle.use_keyboard_spin_controls = false
	paddle.paddle_velocity = Vector2.ZERO
	paddle.paddle_speed = 0.0


func _enable_right_mouse_control(paddle):
	paddle.follow_mouse = false
	paddle.follow_mouse_horizontal = false
	paddle.True_mouse_follow = false
	paddle.mouse_min_x = 16.0
	paddle.mouse_max_x = 344.0
	paddle.mouse_min_y = 400.0
	paddle.mouse_max_y = 784.0
	paddle.keyboard_min_x = 16.0
	paddle.keyboard_max_x = 344.0
	paddle.keyboard_min_y = 400.0
	paddle.keyboard_max_y = 784.0
	paddle.use_mouse_spin_controls = false


func _enable_left_keyboard_control(paddle):
	paddle.keyboard_control = true
	paddle.keyboard_allow_horizontal = true
	paddle.keyboard_min_x = 16.0
	paddle.keyboard_max_x = 344.0
	paddle.keyboard_min_y = 16.0
	paddle.keyboard_max_y = 400.0
	paddle.use_keyboard_spin_controls = false


func _set_client_ball_sync(enabled):
	var ball = $Ball
	ball.set_process(not enabled)
	ball.monitoring = not enabled
	ball.monitorable = not enabled


func _connect_game_sync():
	if _network_manager == null:
		return
	if not _network_manager.paddle_state_received.is_connected(_on_paddle_state_received):
		_network_manager.paddle_state_received.connect(_on_paddle_state_received)
	if not _network_manager.game_state_received.is_connected(_on_game_state_received):
		_network_manager.game_state_received.connect(_on_game_state_received)


func _update_network_sync(delta):
	if _mode != "two_players" or _network_manager == null:
		return
	if _network_manager.multiplayer.multiplayer_peer == null:
		return

	_sync_time += delta
	if _sync_time < NETWORK_SYNC_RATE:
		return
	_sync_time = 0.0

	if _network_role == "client":
		_network_manager.send_paddle_state(_get_paddle_state($Left))
	elif _network_role == "host":
		_network_manager.send_game_state(_get_game_state())


func _on_paddle_state_received(state):
	if _network_role != "host":
		return
	_apply_paddle_state($Left, state)


func _on_game_state_received(state):
	if _network_role != "client":
		return
	_apply_game_state(state)


func _get_game_state():
	return {
		"left": _get_paddle_state($Left),
		"right": _get_paddle_state($Right),
		"ball": _get_ball_state($Ball),
		"left_score": $Scoreboard/LeftScore.text,
		"right_score": $Scoreboard/RightScore.text
	}


func _apply_game_state(state):
	if state.has("left"):
		_apply_paddle_state($Left, state["left"])
	if state.has("right"):
		_apply_paddle_state($Right, state["right"])
	if state.has("ball"):
		_apply_ball_state($Ball, state["ball"])
	if state.has("left_score"):
		$Scoreboard/LeftScore.text = str(state["left_score"])
	if state.has("right_score"):
		$Scoreboard/RightScore.text = str(state["right_score"])


func _get_paddle_state(paddle):
	return {
		"position": paddle.position,
		"rotation": paddle.rotation_degrees,
		"velocity": paddle.paddle_velocity,
		"speed": paddle.paddle_speed,
		"frame": paddle.sprite_frame_index,
		"spin_height": paddle.get_paddle_height_direction()
	}


func _apply_paddle_state(paddle, state):
	paddle.position = state.get("position", paddle.position)
	paddle.rotation_degrees = state.get("rotation", paddle.rotation_degrees)
	paddle.paddle_velocity = state.get("velocity", Vector2.ZERO)
	paddle.paddle_speed = state.get("speed", paddle.paddle_velocity.length())
	if state.has("frame"):
		paddle._set_sprite_frame(int(state["frame"]))
	if state.has("spin_height"):
		paddle._last_spin_height_direction = float(state["spin_height"])


func _get_ball_state(ball):
	return {
		"position": ball.position,
		"visible": ball.visible,
		"height_indicator": ball.height_indicator,
		"height_velocity": ball.height_velocity,
		"velocity": ball.velocity,
		"direction": ball.direction,
		"speed": ball._speed,
		"serve_state": ball._serve_state,
		"serve_delay": ball._serve_collision_delay_remaining,
		"table_bounces_left": ball.table_bounces_left,
		"table_bounces_right": ball.table_bounces_right
	}


func _apply_ball_state(ball, state):
	ball.position = state.get("position", ball.position)
	ball.visible = state.get("visible", ball.visible)
	ball.height_indicator = state.get("height_indicator", ball.height_indicator)
	ball.height_velocity = state.get("height_velocity", ball.height_velocity)
	ball.velocity = state.get("velocity", ball.velocity)
	ball.direction = state.get("direction", ball.direction)
	ball._speed = state.get("speed", ball._speed)
	ball._serve_state = state.get("serve_state", ball._serve_state)
	ball._serve_collision_delay_remaining = state.get("serve_delay", ball._serve_collision_delay_remaining)
	ball.table_bounces_left = state.get("table_bounces_left", ball.table_bounces_left)
	ball.table_bounces_right = state.get("table_bounces_right", ball.table_bounces_right)
	ball._update_collision_delay_visual()
	ball._update_fake_height_visual()


func _connect_network_status():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager == null:
		_update_network_status("Offline")
		return

	if not network_manager.status_changed.is_connected(_on_network_status_changed):
		network_manager.status_changed.connect(_on_network_status_changed)
	_update_network_status(network_manager.last_status)


func _on_network_status_changed(message):
	_update_network_status(message)


func _update_network_status(message):
	var label = get_node_or_null("Scoreboard/NetworkStatus")
	if label != null:
		label.text = message









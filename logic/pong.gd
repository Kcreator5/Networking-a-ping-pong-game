extends Node2D


const NETWORK_SYNC_RATE = 1.0 / 30.0

var _mode = "one_player"
var _selected_side = "right"
var _network_role = "offline"
var _sync_time = 0.0
var _network_manager


func _ready():
	_network_manager = get_node_or_null("/root/NetworkManager")
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
	paddle.follow_mouse = true
	paddle.follow_mouse_horizontal = true
	paddle.True_mouse_follow = true
	paddle.use_mouse_spin_controls = true


func _enable_left_keyboard_control(paddle):
	paddle.keyboard_control = true
	paddle.keyboard_allow_horizontal = true
	paddle.use_keyboard_spin_controls = true


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
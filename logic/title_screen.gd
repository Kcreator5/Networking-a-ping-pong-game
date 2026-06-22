extends Control


func _ready():
	_force_portrait_orientation()
	_layout_for_viewport()
	get_viewport().size_changed.connect(_layout_for_viewport)
	$OnePlayerButton.pressed.connect(_on_one_player_pressed)

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null:
		if not network_manager.status_changed.is_connected(_on_network_status_changed):
			network_manager.status_changed.connect(_on_network_status_changed)
		_on_network_status_changed(network_manager.last_status)


func _force_portrait_orientation():
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)


func _layout_for_viewport():
	_fit_background_to_viewport()
	_layout_play_button()


func _fit_background_to_viewport():
	var background = $Background
	if background.texture == null:
		return

	var viewport_size = get_viewport_rect().size
	var texture_size = background.texture.get_size()
	var fit_scale = min(viewport_size.x / texture_size.x, viewport_size.y / texture_size.y)
	background.position = viewport_size * 0.5
	background.scale = Vector2(fit_scale, fit_scale)
	background.rotation = 0.0


func _layout_play_button():
	var button = $OnePlayerButton
	if button.texture_normal == null:
		return

	var viewport_size = get_viewport_rect().size
	var texture_size = button.texture_normal.get_size()
	var button_width = min(viewport_size.x * 0.72, texture_size.x * 1.65)
	var button_height = button_width * texture_size.y / texture_size.x
	button.size = Vector2(button_width, button_height)
	button.position = Vector2(
		(viewport_size.x - button_width) * 0.5,
		(viewport_size.y - button_height) * 0.58
	)
	button.rotation = 0.0


func _on_one_player_pressed():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null:
		network_manager.close_connection()
	GameMode.mode = "one_player"
	GameMode.selected_side = "right"
	GameMode.network_role = "offline"
	get_tree().change_scene_to_file("res://pong.tscn")


func _on_network_status_changed(message):
	if has_node("NetworkStatus"):
		$NetworkStatus.text = message

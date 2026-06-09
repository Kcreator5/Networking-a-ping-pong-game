extends Control


func _ready():
	$OnePlayerButton.pressed.connect(_on_one_player_pressed)
	$TwoPlayersButton.pressed.connect(_on_two_players_pressed)
	$ExitButton.pressed.connect(_on_exit_pressed)
	$Player1Button.pressed.connect(_on_player_1_pressed)
	$Player2Button.pressed.connect(_on_player_2_pressed)
	_show_side_select(false)

	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null:
		if not network_manager.status_changed.is_connected(_on_network_status_changed):
			network_manager.status_changed.connect(_on_network_status_changed)
		_on_network_status_changed(network_manager.last_status)


func _on_one_player_pressed():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null:
		network_manager.close_connection()
	GameMode.mode = "one_player"
	GameMode.selected_side = "right"
	GameMode.network_role = "offline"
	get_tree().change_scene_to_file("res://pong.tscn")


func _on_two_players_pressed():
	_show_side_select(true)


func _on_player_1_pressed():
	GameMode.mode = "two_players"
	GameMode.selected_side = "right"
	GameMode.network_role = "host"
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null:
		network_manager.host_game()
	get_tree().change_scene_to_file("res://pong.tscn")


func _on_player_2_pressed():
	GameMode.mode = "two_players"
	GameMode.selected_side = "left"
	GameMode.network_role = "client"
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null:
		network_manager.join_game()
	get_tree().change_scene_to_file("res://pong.tscn")


func _on_exit_pressed():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager != null:
		network_manager.close_connection()
	get_tree().quit()


func _show_side_select(visible):
	$Player1Button.visible = visible
	$Player1Button.disabled = not visible
	$Player2Button.visible = visible
	$Player2Button.disabled = not visible


func _on_network_status_changed(message):
	if has_node("NetworkStatus"):
		$NetworkStatus.text = message
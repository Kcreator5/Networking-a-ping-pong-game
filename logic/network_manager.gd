extends Node


signal status_changed(message)
signal match_info_received(info)
signal paddle_state_received(state)
signal game_state_received(state)

const DEFAULT_ADDRESS = "127.0.0.1"
const DEFAULT_PORT = 24567

var is_host = false
var is_connected = false
var last_status = "Offline"
var _next_request_id = 1


func _ready():
	_connect_multiplayer_signals()


func host_game(port = DEFAULT_PORT):
	close_connection()
	_connect_multiplayer_signals()

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 1)
	if error != OK:
		_set_status("Host failed on port %s: %s" % [port, error])
		return false

	multiplayer.multiplayer_peer = peer
	is_host = true
	is_connected = true
	_set_status("Hosting on %s:%s" % [DEFAULT_ADDRESS, port])
	return true


func join_game(address = DEFAULT_ADDRESS, port = DEFAULT_PORT):
	close_connection()
	_connect_multiplayer_signals()

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error != OK:
		_set_status("Join failed for %s:%s: %s" % [address, port, error])
		return false

	multiplayer.multiplayer_peer = peer
	is_host = false
	is_connected = false
	_set_status("Connecting to %s:%s" % [address, port])
	return true


func close_connection():
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_host = false
	is_connected = false
	_set_status("Offline")


func send_paddle_state(state):
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.get_unique_id() == 1:
		return
	submit_paddle_state.rpc_id(1, state)


func send_game_state(state):
	if multiplayer.multiplayer_peer == null or not is_host:
		return
	for peer_id in multiplayer.get_peers():
		receive_game_state.rpc_id(peer_id, state)


@rpc("any_peer", "unreliable")
func submit_paddle_state(state):
	paddle_state_received.emit(state)


@rpc("any_peer", "unreliable")
func receive_game_state(state):
	game_state_received.emit(state)


func send_match_info_request():
	if multiplayer.multiplayer_peer == null or multiplayer.get_unique_id() == 1:
		return

	var request_id = _next_request_id
	_next_request_id += 1
	_set_status("Sending match info request #%s" % request_id)
	request_match_info.rpc_id(1, request_id)


@rpc("any_peer", "reliable")
func request_match_info(request_id):
	var sender_id = multiplayer.get_remote_sender_id()
	var response = {
		"request_id": request_id,
		"host_id": multiplayer.get_unique_id(),
		"message": "pong-host-ready",
		"max_clients": 1
	}
	_set_status("Received request #%s from peer %s" % [request_id, sender_id])
	receive_match_info.rpc_id(sender_id, response)


@rpc("any_peer", "reliable")
func receive_match_info(info):
	_set_status("Received response: %s" % info.get("message", "unknown"))	
	match_info_received.emit(info)


func _connect_multiplayer_signals():
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(peer_id):
	_set_status("Peer connected: %s" % peer_id)


func _on_peer_disconnected(peer_id):
	_set_status("Peer disconnected: %s. Host is still listening." % peer_id)
	if not is_host:
		is_connected = false


func _on_connected_to_server():
	is_connected = true
	_set_status("Connected to host")
	send_match_info_request()


func _on_connection_failed():
	is_connected = false
	_set_status("Connection failed")


func _on_server_disconnected():
	is_connected = false
	_set_status("Server disconnected")


func _set_status(message):
	last_status = message
	print("[Network] " + message)
	status_changed.emit(message)

extends Area2D


func _on_wall_area_entered(area):
	if area.name == "Ball":
		_score_point()
		area.reset()


func _score_point():
	var scoreboard = get_parent().get_node_or_null("Scoreboard")
	if scoreboard == null:
		return

	var label_name = "LeftScore"
	if name == "LeftWall":
		label_name = "RightScore"

	var score_label = scoreboard.get_node_or_null(label_name)
	if score_label == null:
		return

	score_label.text = str(int(score_label.text) + 1)
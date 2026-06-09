extends Area2D


@export var _bounce_direction = 1


func _on_area_entered(area):
	if area.name == "Ball":
		area.bounce_off_horizontal(_bounce_direction)

extends SceneTree

func _initialize() -> void:
	var main = load("res://client/main.tscn").instantiate()
	main._ready()

	main.start_screen.single_player_requested.emit("Tester", "TestCapital")

	for i in range(5):
		main._process(0.1)

	var hex := HexCoord.new(0, 0)
	var s1 := SquadInstance.new("sq1", main._local_owner_id, "rifleman", hex)
	s1.member_ids = ["t1", "t2", "t3"]
	main.state.squads.append(s1)

	var s2 := SquadInstance.new("sq2", main._local_owner_id, "rifleman", hex)
	s2.member_ids = ["t4"]
	main.state.squads.append(s2)

	var s3 := SquadInstance.new("sq3", "p1", "rifleman", hex)
	s3.member_ids = ["t5"]
	main.state.squads.append(s3)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	main.input_controller._unhandled_input(esc)
	print("pause_menu.is_open: ", main.pause_menu.is_open)
	print("squads cap label: '", main.pause_menu._squads_cap_label.text, "'")
	for row in main.pause_menu._squads_box.get_children():
		print("squad row: '", row.text, "'")

	print("VERIFY_DONE")
	quit()

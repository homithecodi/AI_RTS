class_name PlayerController
extends Node
# Everything the human player drives: selection, orders, control groups and
# structure placement.

signal placement_changed
signal status(text: String)

var world: GameWorld = null
var camera: RTSCamera = null

var selection: Array[Entity] = []
var control_groups: Dictionary = {}
var dragging_box: bool = false
var box_start := Vector2.ZERO
var box_current := Vector2.ZERO
var attack_move_armed: bool = false

var placing_id: String = ""
var placing_angle: float = 0.0
var ghost: Node3D = null
var ghost_valid: bool = false
var ghost_reason: String = ""
var _last_click_time: float = -99.0
var _last_click_pos := Vector2.ZERO

func setup(w: GameWorld, cam: RTSCamera) -> void:
	world = w
	camera = cam

# Selected entities are freed the frame they die, so every reader has to drop
# the dangling entries before touching them.
func live_selection() -> Array[Entity]:
	var out: Array[Entity] = []
	for e in selection:
		if is_instance_valid(e) and not e.dead:
			out.append(e)
	return out

func selected_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for e in live_selection():
		if e is Unit:
			out.append(e as Unit)
	return out

func selected_buildings() -> Array[Building]:
	var out: Array[Building] = []
	for e in live_selection():
		if e is Building:
			out.append(e as Building)
	return out

# --- input ---------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)

func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if world == null or camera == null:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if placing_id != "":
				try_place(mb.position)
			else:
				dragging_box = true
				box_start = mb.position
				box_current = mb.position
		else:
			if dragging_box:
				dragging_box = false
				_finish_selection(mb.position)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if placing_id != "":
			cancel_placement()
		else:
			_issue_order(mb.position)

func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	if dragging_box:
		box_current = mm.position
	if placing_id != "":
		_update_ghost(mm.position)

func _handle_key(ev: InputEventKey) -> void:
	if not ev.pressed or ev.echo:
		return
	if ev.ctrl_pressed:
		match ev.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				assign_group(ev.keycode - KEY_0)
			KEY_0:
				recall_group(10)
			KEY_A:
				select_all_army()
		return
	match ev.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			recall_group(ev.keycode - KEY_0)
		KEY_ESCAPE:
			if placing_id != "":
				cancel_placement()
			else:
				attack_move_armed = false
				clear_selection()
		KEY_F:
			if placing_id == "":
				attack_move_armed = not attack_move_armed
				if attack_move_armed:
					emit_status("Attack-move armed - click a destination")
		KEY_X:
			for u in selected_units():
				u.order_stop()
			emit_status("Units stopped")
		KEY_H:
			select_all_army()
		KEY_HOME:
			camera.focus_on(world.base_pos(Defs.TEAM_PLAYER))

# --- selection -----------------------------------------------------------
func _finish_selection(screen_pos: Vector2) -> void:
	var rect := box_rect()
	var is_click := rect.size.length() < 7.0
	if is_click:
		var e := pick_entity(screen_pos)
		if e == null:
			clear_selection()
			return
		var now := Game.elapsed
		var double := (now - _last_click_time) < 0.35 \
			and screen_pos.distance_to(_last_click_pos) < 12.0
		_last_click_time = now
		_last_click_pos = screen_pos
		if double:
			_select_same_type_on_screen(e)
			return
		select([e])
	else:
		_box_select(rect)

func select(entities: Array) -> void:
	for e in selection:
		if is_instance_valid(e):
			e.set_selected(false)
	selection.clear()
	for e in entities:
		if not is_instance_valid(e) or e.dead or e.team != Defs.TEAM_PLAYER:
			continue
		selection.append(e)
		e.set_selected(true)
	Game.selection_changed.emit()

func clear_selection() -> void:
	for e in selection:
		if is_instance_valid(e):
			e.set_selected(false)
	selection.clear()
	Game.selection_changed.emit()

func _select_same_type_on_screen(e: Entity) -> void:
	var out: Array = []
	for other in world.query_units(camera.focus_point(), 120.0):
		if other.team != Defs.TEAM_PLAYER or other.def_id != e.def_id:
			continue
		if _on_screen(other):
			out.append(other)
	if out.is_empty():
		out.append(e)
	select(out)

func _on_screen(e: Entity) -> bool:
	return camera.is_point_visible(e.center())

func _box_select(rect: Rect2) -> void:
	var out: Array = []
	for u in world.units:
		if u.team != Defs.TEAM_PLAYER or u.dead:
			continue
		if rect.has_point(camera.project_ground(u.center())) and camera.is_point_visible(u.center()):
			out.append(u)
	if out.is_empty():
		for b in world.buildings:
			if b.team != Defs.TEAM_PLAYER or b.dead:
				continue
			if rect.has_point(camera.project_ground(b.global_position)):
				out.append(b)
	select(out)

func box_rect() -> Rect2:
	var a := box_start
	var b := box_current
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)),
		Vector2(absf(a.x - b.x), absf(a.y - b.y)))

func pick_entity(screen_pos: Vector2) -> Entity:
	var hit := camera.ray_to_ground(screen_pos)
	if hit.is_empty():
		return null
	var p: Vector3 = hit["point"]
	var candidates: Array = []
	candidates.append_array(world.query_units(p, 9.0))
	candidates.append_array(world.query_buildings(p, 9.0))
	var best: Entity = null
	var best_d := 46.0
	for e in candidates:
		if e.dead:
			continue
		for probe in [e.center(), e.global_position]:
			if not camera.is_point_visible(probe):
				continue
			var d: float = camera.project_ground(probe).distance_to(screen_pos)
			if d < best_d:
				best_d = d
				best = e
	return best

func select_all_army() -> void:
	var out: Array = []
	for u in world.units:
		if u.team == Defs.TEAM_PLAYER and not u.dead:
			out.append(u)
	if out.is_empty():
		emit_status("No combat units available")
		return
	select(out)
	emit_status("Selected %d units" % out.size())

# --- control groups ------------------------------------------------------
func assign_group(index: int) -> void:
	if selection.is_empty():
		return
	var saved: Array = []
	for e in selection:
		if is_instance_valid(e) and e.team == Defs.TEAM_PLAYER:
			saved.append(e)
	control_groups[index] = saved
	emit_status("Group %d assigned (%d)" % [index, saved.size()])

func recall_group(index: int) -> void:
	var saved: Array = control_groups.get(index, [])
	var alive: Array = []
	for e in saved:
		if is_instance_valid(e) and not e.dead and e.team == Defs.TEAM_PLAYER:
			alive.append(e)
	if alive.is_empty():
		emit_status("Group %d is empty" % index)
		return
	select(alive)

# --- orders --------------------------------------------------------------
func _issue_order(screen_pos: Vector2) -> void:
	var hit := camera.ray_to_ground(screen_pos)
	var units := selected_units()
	var buildings := selected_buildings()

	# Right-click on an enemy target: attack it.
	var clicked := pick_entity(screen_pos)
	if clicked != null and clicked.team != Defs.TEAM_PLAYER:
		if units.is_empty():
			return
		for u in units:
			u.order_attack(clicked)
		attack_move_armed = false
		emit_status("Attacking %s" % clicked.display_name())
		return

	# Right-click on one of your own producers.
	if clicked != null and clicked is Building and clicked.team == Defs.TEAM_PLAYER \
			and not hit.is_empty():
		var target: Building = clicked as Building
		if target.produces().is_empty():
			if buildings.is_empty():
				select([target])
				camera.focus_on(target.global_position)
			return
		if units.is_empty() and buildings.is_empty():
			# Quick-build: queue the cheapest unit this building can make.
			var best_id := ""
			var best_cost := INF
			for uid in target.produces():
				var c := float(Defs.unit_def(String(uid)).get("cost", 99999))
				if target.can_queue(String(uid)) and c < best_cost:
					best_cost = c
					best_id = String(uid)
			if best_id != "":
				target.enqueue(best_id)
				emit_status("Queued %s" % String(Defs.unit_def(best_id).get("name", best_id)))
			else:
				emit_status("Not enough ore")
			return
		var set_any := false
		for b in buildings:
			if not b.produces().is_empty():
				b.rally_point = hit["point"]
				b.rally_set = true
				b.rally_point.y = world.terrain.height_at(b.rally_point.x, b.rally_point.z)
				set_any = true
		emit_status("Rally point set" if set_any else "No producers selected")
		return

	if hit.is_empty():
		return
	var dest: Vector3 = hit["point"]
	dest = world.clamp_to_map(dest)

	if not buildings.is_empty() and units.is_empty():
		var set_any := false
		for b in buildings:
			if not b.produces().is_empty():
				b.rally_point = dest
				b.rally_set = true
				b.rally_point.y = world.terrain.height_at(dest.x, dest.z)
				set_any = true
		emit_status("Rally point set" if set_any else "No producers selected")
		return

	if units.is_empty():
		return

	_issue_move(units, dest, attack_move_armed)
	attack_move_armed = false

func command_move(units: Array[Unit], dest: Vector3, attacking: bool) -> void:
	_issue_move(units, dest, attacking)

func _issue_move(units: Array[Unit], dest: Vector3, attacking: bool) -> void:
	var usable: Array[Unit] = []
	for u in units:
		if not u.dead:
			usable.append(u)
	if usable.is_empty():
		return
	var spacing := 3.0
	for u in usable:
		spacing = maxf(spacing, u.radius() * 2.2 + 1.2)
	var dir := Vector3.ZERO
	for u in usable:
		dir += u.global_position - dest
		dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = camera.focus.global_position - dest
		dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()

	var offsets := _formation_offsets(usable.size(), dir, spacing)
	for i in usable.size():
		var u2: Unit = usable[i]
		if attacking:
			u2.order_attack_move(dest, offsets[i])
		else:
			u2.order_move(dest, offsets[i])
	emit_status(("Attack-move: %d units" % usable.size()) if attacking
		else ("Moving %d units" % usable.size()))

func _formation_offsets(count: int, dir: Vector3, spacing: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if count <= 1:
		out.append(Vector3.ZERO)
		return out
	var fwd := dir
	var right := Vector3(-fwd.z, 0, fwd.x)
	var cols := int(ceil(sqrt(float(count))))
	var rows := int(ceil(float(count) / float(cols)))
	for i in count:
		var c := i % cols
		var r := i / cols
		var ox := (float(c) - (float(cols) - 1.0) * 0.5) * spacing
		var oz := (float(r) - (float(rows) - 1.0) * 0.5) * spacing
		out.append(right * ox + fwd * oz)
	return out

# --- placement -----------------------------------------------------------
func begin_placement(building_id: String) -> void:
	if world == null:
		return
	var d := Defs.building_def(building_id)
	if d.is_empty():
		return
	cancel_placement()
	placing_id = building_id
	placing_angle = _best_facing(building_id)
	ghost = BuildingModels.build(building_id, Defs.TEAM_PLAYER)["root"]
	ghost.visible = false
	world.add_child(ghost)
	_set_ghost_material(ghost, true)
	placement_changed.emit()

func _best_facing(building_id: String) -> float:
	var forward := Vector3(-sin(camera.yaw), 0, -cos(camera.yaw))
	if String(building_id) == "defense_tower":
		var enemy := world.base_pos(Defs.TEAM_ENEMY)
		return atan2(enemy.x - camera.focus_point().x, enemy.z - camera.focus_point().z)
	return atan2(forward.x, forward.z)

func _set_ghost_material(node: Node, ghost_mode: bool) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var color := Color(0.35, 1.0, 0.45) if ghost_mode else Color(1.0, 0.3, 0.25)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(color.r, color.g, color.b, 0.42)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_set_ghost_material(child, ghost_mode)

func _update_ghost(screen_pos: Vector2) -> void:
	var hit := camera.ray_to_ground(screen_pos)
	if hit.is_empty():
		ghost.visible = false
		return
	ghost.visible = true
	var pos: Vector3 = hit["point"]
	pos.y = world.terrain.height_at(pos.x, pos.z)
	ghost.position = pos
	ghost.rotation.y = placing_angle
	var check := world.can_place(placing_id, pos, Defs.TEAM_PLAYER)
	ghost_valid = bool(check["ok"])
	ghost_reason = String(check["reason"])
	_set_ghost_material(ghost, ghost_valid)

func try_place(screen_pos: Vector2) -> void:
	if placing_id == "":
		return
	var hit := camera.ray_to_ground(screen_pos)
	if hit.is_empty():
		emit_status("Invalid location")
		return
	var pos: Vector3 = hit["point"]
	var f := Game.faction(Defs.TEAM_PLAYER)
	var d := Defs.building_def(placing_id)
	var check := world.can_place(placing_id, pos, Defs.TEAM_PLAYER)
	if not bool(check["ok"]):
		emit_status(String(check["reason"]))
		return
	if f == null or not f.spend(float(d.get("cost", 0))):
		emit_status("Not enough ore")
		return
	pos.y = world.terrain.height_at(pos.x, pos.z)
	world.spawn_building(placing_id, Defs.TEAM_PLAYER, pos, placing_angle, false)
	emit_status("%s under construction" % String(d.get("name", placing_id)))
	# Keep placing so a player can queue up several structures quickly.
	if f != null and not f.can_afford(float(d.get("cost", 0))):
		cancel_placement()

func cancel_placement() -> void:
	if ghost != null and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	placing_id = ""
	ghost_valid = false
	ghost_reason = ""
	placement_changed.emit()

func emit_status(text: String) -> void:
	status.emit(text)

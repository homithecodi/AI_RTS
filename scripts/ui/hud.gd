class_name HUD
extends CanvasLayer

const BUILD_ORDER := ["power_plant", "refinery", "barracks", "war_factory",
	"defense_tower"]

var world: GameWorld = null
var camera: RTSCamera = null
var controller: PlayerController = null
var ai: EnemyAI = null

var root: Control
var top_bar: PanelContainer
var minimap: Minimap
var build_panel: PanelContainer
var build_box: VBoxContainer
var prod_panel: PanelContainer
var prod_box: VBoxContainer
var sel_panel: PanelContainer
var sel_box: VBoxContainer
var event_log: VBoxContainer
var overlay: Control
var overlay_label: Label
var help_panel: PanelContainer
var speed_label: Label
var ore_value: Label
var income_value: Label
var power_value: Label
var power_bar: ProgressBar
var army_value: Label
var warn_label: Label

var _messages: Array[Dictionary] = []
var _help_visible := false
var _refresh_timer := 0.0

func setup(w: GameWorld, cam: RTSCamera, ctrl: PlayerController,
		enemy_ai: EnemyAI) -> void:
	world = w
	camera = cam
	controller = ctrl
	ai = enemy_ai
	_build_ui()
	Game.resources_changed.connect(_on_resources_changed)
	Game.selection_changed.connect(_refresh_selection)
	Game.game_over.connect(_on_game_over)
	controller.status.connect(_on_status)
	ai.ai_event.connect(_on_ai_status)
	_refresh_top()
	_refresh_selection()
	_on_status("Welcome, Commander. Build up and destroy the enemy base.")
	_on_status("Left click selects, right click orders. F = attack-move, X = stop.")

# --- construction --------------------------------------------------------
func _build_ui() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_top_bar()
	_build_minimap()
	_build_build_menu()
	_build_production_panel()
	_build_selection_panel()
	_build_event_log()
	_build_help()
	_build_overlay()

func _style(bg: Color = Color(0.05, 0.06, 0.08, 0.86),
		border: Color = Color(0.30, 0.34, 0.40, 0.9)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _panel(mouse_ignore: bool = true) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE if mouse_ignore \
		else Control.MOUSE_FILTER_STOP
	return p

func _label(text: String, size: int = 13, color: Color = Color(0.88, 0.90, 0.94)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _vbox(sep: int = 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v

func _build_top_bar() -> void:
	top_bar = _panel()
	top_bar.anchor_right = 1.0
	top_bar.offset_left = 6
	top_bar.offset_right = -6
	top_bar.offset_top = 6
	top_bar.offset_bottom = 48
	root.add_child(top_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(row)

	ore_value = _label("ORE 0", 17, Color(0.98, 0.82, 0.32))
	row.add_child(ore_value)
	income_value = _label("+0.0/s", 13, Color(0.72, 0.78, 0.70))
	row.add_child(income_value)

	var power_box := _vbox(2)
	power_box.custom_minimum_size = Vector2(190, 0)
	row.add_child(power_box)
	var power_row := HBoxContainer.new()
	power_row.add_theme_constant_override("separation", 8)
	power_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_box.add_child(power_row)
	power_row.add_child(_label("POWER", 13, Color(0.70, 0.80, 0.95)))
	power_value = _label("0 / 0", 13)
	power_row.add_child(power_value)
	power_bar = ProgressBar.new()
	power_bar.show_percentage = false
	power_bar.custom_minimum_size = Vector2(180, 8)
	power_bar.max_value = 1.0
	power_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_box.add_child(power_bar)

	army_value = _label("ARMY 0", 14, Color(0.80, 0.84, 0.90))
	row.add_child(army_value)

	warn_label = _label("", 14, Color(1.0, 0.45, 0.30))
	row.add_child(warn_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	speed_label = _label("1x   SPACE pause   [ ] speed", 12, Color(0.62, 0.66, 0.72))
	row.add_child(speed_label)

	var help_btn := Button.new()
	help_btn.text = "HELP"
	help_btn.tooltip_text = "Show or hide the controls list"
	help_btn.pressed.connect(_toggle_help)
	row.add_child(help_btn)

func _toggle_help() -> void:
	_help_visible = not _help_visible
	help_panel.visible = _help_visible

func toggle_help() -> void:
	_toggle_help()

func restart() -> void:
	_restart()

func _build_minimap() -> void:
	minimap = Minimap.new()
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = 10
	minimap.offset_right = 246
	minimap.offset_top = -246
	minimap.offset_bottom = -10
	root.add_child(minimap)

func _build_build_menu() -> void:
	build_panel = _panel()
	build_panel.anchor_left = 1.0
	build_panel.anchor_right = 1.0
	build_panel.offset_left = -222
	build_panel.offset_right = -10
	build_panel.offset_top = 56
	build_panel.offset_bottom = 336
	root.add_child(build_panel)

	build_box = _vbox(3)
	build_panel.add_child(build_box)
	build_box.add_child(_label("CONSTRUCT", 15, Color(0.98, 0.82, 0.32)))
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_box.add_child(sep)

	for id in BUILD_ORDER:
		var d := Defs.building_def(id)
		var b := Button.new()
		b.text = "%s  %d" % [d.get("name", id), int(d.get("cost", 0))]
		b.tooltip_text = String(d.get("desc", ""))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(196, 26)
		b.pressed.connect(_on_build_pressed.bind(id))
		build_box.add_child(b)

func _build_production_panel() -> void:
	prod_panel = _panel()
	prod_panel.anchor_left = 1.0
	prod_panel.anchor_right = 1.0
	prod_panel.anchor_top = 1.0
	prod_panel.anchor_bottom = 1.0
	prod_panel.offset_left = -222
	prod_panel.offset_right = -10
	prod_panel.offset_top = -250
	prod_panel.offset_bottom = -10
	prod_panel.visible = false
	root.add_child(prod_panel)
	prod_box = _vbox(3)
	prod_panel.add_child(prod_box)

func _build_selection_panel() -> void:
	sel_panel = _panel()
	sel_panel.anchor_left = 0.5
	sel_panel.anchor_right = 0.5
	sel_panel.anchor_top = 1.0
	sel_panel.anchor_bottom = 1.0
	sel_panel.offset_left = -250
	sel_panel.offset_right = 250
	sel_panel.offset_top = -140
	sel_panel.offset_bottom = -10
	sel_panel.visible = false
	root.add_child(sel_panel)
	sel_box = _vbox(2)
	sel_panel.add_child(sel_box)

func _build_event_log() -> void:
	event_log = _vbox(2)
	event_log.anchor_right = 1.0
	event_log.offset_left = 10
	event_log.offset_top = 56
	event_log.offset_right = -240
	root.add_child(event_log)

func _build_help() -> void:
	help_panel = _panel()
	help_panel.anchor_left = 0.5
	help_panel.anchor_right = 0.5
	help_panel.anchor_top = 0.5
	help_panel.anchor_bottom = 0.5
	help_panel.offset_left = -250
	help_panel.offset_right = 250
	help_panel.offset_top = -200
	help_panel.offset_bottom = 200
	help_panel.visible = false
	root.add_child(help_panel)
	var v := _vbox(5)
	help_panel.add_child(v)
	v.add_child(_label("CONTROLS", 18, Color(0.98, 0.82, 0.32)))
	var lines := [
		"Left mouse        select, drag for a box selection, double click for all of a type",
		"Right mouse       move, attack, set rally point, right click a barracks to quick build",
		"W A S D / arrows  pan camera          Q / E  rotate          mouse wheel  zoom",
		"Middle drag       rotate and pitch the camera              Home  jump to base",
		"F then click      attack-move          X  stop          H  select entire army",
		"Ctrl + 1..9       assign control group        1..9  recall control group",
		"Space             pause            [ and ]  change game speed",
		"Esc               cancel placement or selection",
		"",
		"ORECOMBAT",
		"Riflemen beat other infantry. Tanks beat vehicles and structures.",
		"Rocketeers and Missile Tanks hit vehicles hard and splash nearby units.",
		"A Refinery only collects from ore fields inside its radius - put more next to ore.",
		"Build Power Plants when the LOW POWER warning appears: short power slows everything.",
	]
	for line in lines:
		v.add_child(_label(line, 13))
	var close := Button.new()
	close.text = "CLOSE"
	close.pressed.connect(_close_help)
	v.add_child(close)

func _close_help() -> void:
	_help_visible = false
	help_panel.visible = false

func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	root.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var center := VBoxContainer.new()
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.anchor_top = 0.5
	center.anchor_bottom = 0.5
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	overlay_label = _label("VICTORY", 52, Color(1, 1, 1))
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(overlay_label)

	var again := Button.new()
	again.text = "PLAY AGAIN"
	again.custom_minimum_size = Vector2(180, 34)
	again.pressed.connect(_restart)
	center.add_child(again)

func _restart() -> void:
	get_tree().paused = false
	Game.reset_match()
	get_tree().reload_current_scene()

# --- refresh -------------------------------------------------------------
func _process(_delta: float) -> void:
	if speed_label != null:
		var s := "%s   %s   [ ] speed" % ["%dx" % int(round(Game.game_speed * 10.0) / 10.0),
			"PAUSED" if Game.paused else "running"]
		if speed_label.text != s:
			speed_label.text = s
	_age_messages()
	if controller != null and controller.placing_id != "" and not controller.ghost_valid:
		if warn_label.text != controller.ghost_reason:
			warn_label.text = controller.ghost_reason
	# Progress bars and affordability have to keep ticking between selections.
	_refresh_timer -= _delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.25
		if prod_panel.visible:
			_refresh_production()
		if sel_panel.visible:
			_refresh_selection_panel()

func _on_resources_changed(_team: int) -> void:
	_refresh_top()

func _refresh_top() -> void:
	var f := Game.faction(Defs.TEAM_PLAYER)
	if f == null:
		return
	ore_value.text = "ORE  %d" % int(f.ore)
	income_value.text = "+%.1f/s" % (f.income_rate * f.income_bonus)
	power_value.text = "%d / %d" % [int(f.power_produced), int(f.power_used)]
	var ratio := f.power_ratio()
	power_bar.value = clampf(float(f.power_produced)
		/ maxf(float(f.power_used), 1.0), 0.0, 1.0)
	power_value.add_theme_color_override("font_color",
		Color(1.0, 0.4, 0.3) if f.is_low_power() else Color(0.88, 0.90, 0.94))
	var enemy := Game.faction(Defs.TEAM_ENEMY)
	var mine := f.units.size() + f.buildings.size()
	var theirs := 0 if enemy == null else enemy.units.size() + enemy.buildings.size()
	army_value.text = "FORCES  %d  vs  %d" % [mine, theirs]
	if f.is_low_power():
		warn_label.text = "LOW POWER"
	elif controller != null and controller.placing_id != "" and not controller.ghost_valid:
		warn_label.text = controller.ghost_reason
	elif Game.match_over:
		warn_label.text = ""
	else:
		warn_label.text = ""

func _refresh_selection() -> void:
	_refresh_production()
	_refresh_selection_panel()

func _refresh_selection_panel() -> void:
	_clear(sel_box)
	var sel := controller.live_selection()
	sel_panel.visible = not sel.is_empty()
	if sel.is_empty():
		return
	var counts: Dictionary = {}
	var total_hp := 0.0
	var max_hp := 0.0
	for e in sel:
		counts[e.def_id] = int(counts.get(e.def_id, 0)) + 1
		total_hp += e.hp
		max_hp += e.max_hp

	if sel.size() == 1:
		var e := sel[0]
		var d := e.def
		var name_row := HBoxContainer.new()
		name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sel_box.add_child(name_row)
		name_row.add_child(_label(String(d.get("name", e.def_id)), 18,
			Defs.team_color(e.team)))
		name_row.add_child(_label("   HP %d / %d" % [int(e.hp), int(e.max_hp)], 14,
			Color(0.6, 0.9, 0.6)))
		if d.has("damage"):
			var line := "Damage %d   Range %d   Speed %.1f" % [
				int(d.get("damage", 0)), int(d.get("range", 0)),
				float(d.get("speed", 0))]
			if d.has("cooldown"):
				line += "   Rate %.2fs" % float(d.get("cooldown", 1))
			sel_box.add_child(_label(line, 12, Color(0.74, 0.78, 0.84)))
		elif d.has("power"):
			var p := float(d.get("power", 0))
			var ptext := ("Supplies %d power" % int(p)) if p > 0.0 \
				else ("Uses %d power" % int(-p))
			sel_box.add_child(_label(ptext, 12, Color(0.74, 0.78, 0.84)))
			var b := e as Building
			if b != null and d.has("gather_radius"):
				sel_box.add_child(_label("Collecting %.1f ore/sec" % b.income,
					12, Color(0.98, 0.82, 0.32)))
		if d.has("desc"):
			sel_box.add_child(_label(String(d.get("desc", "")), 11,
				Color(0.56, 0.60, 0.66)))
	else:
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sel_box.add_child(head)
		head.add_child(_label("%d selected" % sel.size(), 18, Color(0.98, 0.82, 0.32)))
		head.add_child(_label("   HP %d / %d" % [int(total_hp), int(max_hp)], 14))
		var cols := 0
		for key in counts:
			cols += 1
			var nm := String(Defs.unit_def(key).get("name",
				Defs.building_def(key).get("name", key)))
			sel_box.add_child(_label("%d x %s" % [int(counts[key]), nm], 13,
				Color(0.80, 0.84, 0.90)))
			if cols >= 4:
				break

func _refresh_production() -> void:
	_clear(prod_box)
	var producers: Array[Building] = []
	for e in controller.live_selection():
		if e is Building:
			var b := e as Building
			if not b.produces().is_empty():
				producers.append(b)
	prod_panel.visible = not producers.is_empty()
	if producers.is_empty():
		return
	var f := Game.faction(Defs.TEAM_PLAYER)
	for i in mini(producers.size(), 2):
		var b := producers[i]
		var head := _label(b.display_name().to_upper(), 14, Color(0.98, 0.82, 0.32))
		prod_box.add_child(head)
		if not b.active:
			var pct := int(b.build_progress * 100.0)
			prod_box.add_child(_progress_bar(b.build_progress, 1.0, Vector2(190, 8)))
			prod_box.add_child(_label("Under construction  %d%%" % pct, 11))
			continue
		for uid in b.produces():
			var uid_str := String(uid)
			var ud := Defs.unit_def(uid_str)
			var cost := int(ud.get("cost", 0))
			var btn := Button.new()
			btn.text = "%s  %d" % [ud.get("name", uid_str), cost]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(190, 24)
			btn.tooltip_text = String(ud.get("desc", ""))
			btn.disabled = f == null or not f.can_afford(float(cost)) \
				or b.queue.size() >= 5
			btn.pressed.connect(_queue_unit.bind(b, uid_str))
			prod_box.add_child(btn)
		if not b.queue.is_empty():
			var idx := 0
			for item in b.queue:
				var nm := String(Defs.unit_def(String(item["id"])).get("name", "?"))
				var row := HBoxContainer.new()
				row.mouse_filter = Control.MOUSE_FILTER_IGNORE
				prod_box.add_child(row)
				if idx == 0:
					var total := maxf(float(item["total"]), 0.001)
					var done := maxf(total - float(item["remaining"]), 0.0)
					row.add_child(_progress_bar(done, total, Vector2(120, 12)))
				else:
					var lbl := _label("...", 12, Color(0.6, 0.64, 0.70))
					lbl.custom_minimum_size = Vector2(120, 12)
					row.add_child(lbl)
				row.add_child(_label(" %s" % nm, 12))
				var cancel := Button.new()
				cancel.text = "x"
				cancel.custom_minimum_size = Vector2(24, 18)
				cancel.tooltip_text = "Cancel this unit (75% refund)"
				var this_index := idx
				var this_building := b
				cancel.pressed.connect(_cancel_queue.bind(b, idx))
				row.add_child(cancel)
				idx += 1

func _queue_unit(b: Building, unit_id: String) -> void:
	if b == null or not is_instance_valid(b):
		return
	if b.enqueue(unit_id):
		_on_status("Queued %s" % String(Defs.unit_def(unit_id).get("name", unit_id)))
	else:
		_on_status("Not enough ore")

func _cancel_queue(b: Building, index: int) -> void:
	if b != null and is_instance_valid(b):
		b.cancel_queue_entry(index)
		_refresh_production()

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _progress_bar(value: float, max_value: float, size: Vector2) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = max_value
	pb.value = value
	pb.custom_minimum_size = size
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb

# --- build menu ----------------------------------------------------------
func _on_build_pressed(id: String) -> void:
	var f := Game.faction(Defs.TEAM_PLAYER)
	var cost := float(Defs.building_def(id).get("cost", 0))
	if f == null or not f.can_afford(cost):
		_on_status("Not enough ore")
		return
	if controller.placing_id == id:
		controller.cancel_placement()
	else:
		controller.begin_placement(id)
		_on_status("Place %s - left click to build, right click to cancel"
			% String(Defs.building_def(id).get("name", id)))

func _on_ai_status(text: String) -> void:
	notify(text, Defs.TEAM_ENEMY)

func _on_status(text: String, team: int = Defs.TEAM_PLAYER) -> void:
	notify(text, team)

func notify(text: String, team: int = Defs.TEAM_PLAYER) -> void:
	var color := Defs.team_color(team).lerp(Color.WHITE, 0.35)
	_messages.push_front({"text": text, "color": color, "life": 9.0})
	while _messages.size() > 8:
		_messages.pop_back()
	_rebuild_log()

func _rebuild_log() -> void:
	_clear(event_log)
	for m in _messages:
		event_log.add_child(_label(String(m["text"]), 12, m["color"]))

func _age_messages() -> void:
	var changed := false
	for m in _messages:
		m["life"] = float(m["life"]) - get_process_delta_time()
		if float(m["life"]) <= 0.0:
			changed = true
	if changed:
		_messages = _messages.filter(func(m: Dictionary) -> bool:
			return float(m["life"]) > 0.0)
		_rebuild_log()

func _on_game_over(win: int) -> void:
	overlay.visible = true
	if win == Defs.TEAM_PLAYER:
		overlay_label.text = "VICTORY"
		overlay_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	else:
		overlay_label.text = "DEFEAT"
		overlay_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
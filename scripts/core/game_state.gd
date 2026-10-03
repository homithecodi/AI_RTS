extends Node
# Autoload: Game

signal resources_changed(team: int)
signal selection_changed
signal game_over(winner: int)
signal message(text: String, team: int)

var factions: Dictionary = {}
var world: Node3D = null
var game_speed: float = 1.0
var paused: bool = false
var elapsed: float = 0.0
var match_over: bool = false
var started: bool = false
var winner: int = -1
var ai_faction: Faction = null
var _ui_timer: float = 0.0

func _ready() -> void:
	reset_match()

# The Game autoload survives reload_current_scene(), so it has to drop every
# reference into the old scene. Otherwise the next match keeps a faction roster
# full of freed units and structures.
func reset_match() -> void:
	Defs.setup_input()
	factions.clear()

	var player := Faction.new()
	player.team = Defs.TEAM_PLAYER
	player.is_ai = false
	factions[Defs.TEAM_PLAYER] = player

	var ai := Faction.new()
	ai.team = Defs.TEAM_ENEMY
	ai.is_ai = true
	ai.ore = Defs.AI_START_ORE
	factions[Defs.TEAM_ENEMY] = ai
	ai_faction = ai

	world = null
	elapsed = 0.0
	match_over = false
	started = false
	winner = -1
	paused = false
	_ui_timer = 0.0
	set_speed(1.0)
	get_tree().paused = false

func faction(team: int) -> Faction:
	return factions.get(team, null)

func other_team(team: int) -> int:
	return Defs.TEAM_ENEMY if team == Defs.TEAM_PLAYER else Defs.TEAM_PLAYER

func register_unit(unit: Unit) -> void:
	var f := faction(unit.team)
	if f and not f.units.has(unit):
		f.units.append(unit)

func unregister_unit(unit: Unit) -> void:
	var f := faction(unit.team)
	if f:
		f.units.erase(unit)
	if world and world.has_method("unregister_unit"):
		world.unregister_unit(unit)

func register_building(b: Building) -> void:
	var f := faction(b.team)
	if f and not f.buildings.has(b):
		f.buildings.append(b)
	if f:
		f.rebuild_power()

func unregister_building(b: Building) -> void:
	var f := faction(b.team)
	if f:
		f.buildings.erase(b)
		f.rebuild_power()
	if world and world.has_method("unregister_building"):
		world.unregister_building(b)

func notify_resources(team: int) -> void:
	resources_changed.emit(team)

func _process(delta: float) -> void:
	if paused or match_over:
		return
	elapsed += delta
	for team in factions:
		var f: Faction = factions[team]
		if f.is_alive():
			f.tick_economy(delta)
	_ui_timer -= delta
	if _ui_timer <= 0.0:
		_ui_timer = 0.1
		resources_changed.emit(Defs.TEAM_PLAYER)

func set_speed(value: float) -> void:
	game_speed = value
	Engine.time_scale = value

func toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused

func cycle_speed(dir: int) -> void:
	var speeds := [0.5, 1.0, 2.0, 3.0]
	var idx := speeds.find(game_speed)
	if idx < 0:
		idx = 1
	set_speed(speeds[clampi(idx + dir, 0, speeds.size() - 1)])

func check_victory() -> void:
	if match_over or not started:
		return
	var p: Faction = factions[Defs.TEAM_PLAYER]
	var e: Faction = factions[Defs.TEAM_ENEMY]
	if p.is_alive() and not e.is_alive():
		_finish(Defs.TEAM_PLAYER)
	elif e.is_alive() and not p.is_alive():
		_finish(Defs.TEAM_ENEMY)

func _finish(win: int) -> void:
	match_over = true
	winner = win
	game_over.emit(win)
	message.emit("VICTORY" if win == Defs.TEAM_PLAYER else "DEFEAT", win)
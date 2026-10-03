class_name Defs
extends RefCounted
# Single source of truth for balance data and input bindings.
#
# Everything the designer would want to touch lives here: unit and structure stats,
# team colours, starting resources, and the key bindings. No other script hard-codes
# a cost, a hit point or a key.
#
# Stat conventions used throughout the codebase:
#   * "power" is signed: positive generates, negative consumes.
#   * "cost"/"build_time"/"hp"/"range"/"damage" are plain float seconds and units.
#   * "splash" is a radius, and doubles as the flag for "area damage" (> 0.1).
#   * "projectile" true means the unit fires a travelling shell instead of a hitscan
#     tracer.
#   * "size_x"/"size_z" are the footprint used for collision and the minimap;
#     "footprint" is the circular radius used for spacing and placement checks.

const TEAM_PLAYER := 0
const TEAM_ENEMY := 1

const COL_PLAYER := Color(0.28, 0.62, 1.0)
const COL_ENEMY := Color(0.98, 0.31, 0.22)
const COL_NEUTRAL := Color(0.7, 0.7, 0.7)

# --- units ----------------------------------------------------------------
const UNITS := {
	"rifleman": {
		"name": "Rifleman",
		"kind": "infantry",
		"cost": 100, "build_time": 6.0,
		"hp": 110.0, "speed": 6.2,
		"range": 13.0, "damage": 11.0, "cooldown": 0.85,
		"vs_infantry": 1.5, "vs_vehicle": 0.35,
		"splash": 0.0, "projectile": false,
		"producer": "barracks", "sight": 30.0, "radius": 0.9, "height": 2.9,
		"desc": "Cheap infantry. Strong against other infantry, helpless against armour.",
	},
	"rocketeer": {
		"name": "Rocketeer",
		"kind": "infantry",
		"cost": 220, "build_time": 10.0,
		"hp": 90.0, "speed": 5.0,
		"range": 28.0, "damage": 46.0, "cooldown": 3.4,
		"vs_infantry": 0.45, "vs_vehicle": 1.25,
		"splash": 4.5, "projectile": true,
		"producer": "barracks", "sight": 38.0, "radius": 0.9, "height": 2.9,
		"desc": "Long range rocket team. Splash damage, best against vehicles.",
	},
	"scout": {
		"name": "Scout Car",
		"kind": "vehicle",
		"cost": 350, "build_time": 10.0,
		"hp": 260.0, "speed": 15.5,
		"range": 17.0, "damage": 13.0, "cooldown": 0.55,
		"vs_infantry": 1.1, "vs_vehicle": 0.85,
		"splash": 0.0, "projectile": false,
		"producer": "war_factory", "sight": 40.0, "radius": 1.4, "height": 2.6,
		"desc": "Fast recon car with a light machine gun. Excellent for scouting and harassment.",
	},
	"tank": {
		"name": "Paladin Tank",
		"kind": "vehicle",
		"cost": 800, "build_time": 16.0,
		"hp": 900.0, "speed": 8.5,
		"range": 21.0, "damage": 72.0, "cooldown": 1.75,
		"vs_infantry": 0.8, "vs_vehicle": 1.45,
		"splash": 2.5, "projectile": false,
		"producer": "war_factory", "sight": 40.0, "radius": 2.0, "height": 4.2,
		"desc": "Main battle tank. Heavy armour and a high velocity cannon.",
	},
	"missile_tank": {
		"name": "Guardian Tank",
		"kind": "vehicle",
		"cost": 1150, "build_time": 21.0,
		"hp": 620.0, "speed": 7.2,
		"range": 32.0, "damage": 88.0, "cooldown": 3.0,
		"vs_infantry": 0.55, "vs_vehicle": 1.65,
		"splash": 5.5, "projectile": true,
		"producer": "war_factory", "sight": 44.0, "radius": 2.0, "height": 4.2,
		"desc": "Missile artillery on a tank chassis. Long range area damage.",
	},
}

# --- structures ----------------------------------------------------------
const BUILDINGS := {
	"power_plant": {
		"name": "Power Plant",
		"cost": 800, "build_time": 13.0, "hp": 1400.0,
		"power": 100, "footprint": 8.0, "height": 5.0,
		"producer": null, "size_x": 8.0, "size_z": 8.0,
		"desc": "Supplies 100 power. Structures and units slow down if you are short.",
	},
	"refinery": {
		"name": "Ore Refinery",
		"cost": 2000, "build_time": 22.0, "hp": 2100.0,
		"power": -50, "footprint": 9.0, "height": 6.5,
		"producer": null, "size_x": 10.0, "size_z": 10.0,
		"gather_radius": 52.0, "gather_rate": 2.4, "max_nodes": 4,
		"desc": "Collects ore from nearby ore fields. Your primary source of income.",
	},
	"barracks": {
		"name": "Barracks",
		"cost": 800, "build_time": 15.0, "hp": 1600.0,
		"power": -20, "footprint": 8.0, "height": 4.0,
		"producer": null, "size_x": 8.0, "size_z": 7.0,
		"units": ["rifleman", "rocketeer"],
		"desc": "Trains infantry. Has a rally point for new recruits.",
	},
	"war_factory": {
		"name": "War Factory",
		"cost": 2000, "build_time": 25.0, "hp": 2200.0,
		"power": -60, "footprint": 12.0, "height": 5.0,
		"producer": null, "size_x": 12.0, "size_z": 9.0,
		"units": ["scout", "tank", "missile_tank"],
		"desc": "Produces vehicles. Powerful but power hungry.",
	},
	"defense_tower": {
		"name": "Defense Tower",
		"cost": 900, "build_time": 13.0, "hp": 1700.0,
		"power": -30, "footprint": 4.0, "height": 7.0,
		"producer": null, "size_x": 4.0, "size_z": 4.0,
		"range": 33.0, "damage": 58.0, "cooldown": 1.15,
		"splash": 0.0, "sight": 36.0,
		"desc": "Automated turret. Defends an area and ignores the low power speed penalty.",
	},
}

# --- economy --------------------------------------------------------------
const START_ORE := 5000.0
const AI_START_ORE := 4200.0
const ORE_PER_NODE := 1600.0

## Look up a unit definition. Returns an empty Dictionary for unknown ids, so
## callers use .get() with their own defaults rather than indexing blindly.
static func unit_def(id: String) -> Dictionary:
	return UNITS.get(id, {})

## Look up a structure definition. Same empty-dictionary fallback as unit_def().
static func building_def(id: String) -> Dictionary:
	return BUILDINGS.get(id, {})

static func team_color(team: int) -> Color:
	if team == TEAM_PLAYER:
		return COL_PLAYER
	if team == TEAM_ENEMY:
		return COL_ENEMY
	return COL_NEUTRAL

static func team_name(team: int) -> String:
	if team == TEAM_PLAYER:
		return "BLUE"
	if team == TEAM_ENEMY:
		return "RED"
	return "NEUTRAL"

## Register the key bindings in code rather than in project settings so they behave
## identically on every machine and keyboard layout. Physical keycodes are used, so
## the bindings follow the physical key position rather than the user's layout.
##
## Safe to call more than once: existing actions are erased first, which is what
## makes it usable from Game.reset_match().
static func setup_input() -> void:
	_action(&"cam_left", [KEY_A, KEY_LEFT])
	_action(&"cam_right", [KEY_D, KEY_RIGHT])
	_action(&"cam_up", [KEY_W, KEY_UP])
	_action(&"cam_down", [KEY_S, KEY_DOWN])
	_action(&"cam_rotate_left", [KEY_Q])
	_action(&"cam_rotate_right", [KEY_E])
	_action(&"cam_center", [KEY_HOME])
	_action(&"cam_zoom_in", [KEY_EQUAL, KEY_KP_ADD])
	_action(&"cam_zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT])
	_action(&"order_attack_move", [KEY_F])
	_action(&"order_stop", [KEY_X])
	_action(&"select_all_army", [KEY_H])
	_action(&"game_pause", [KEY_SPACE])
	_action(&"game_speed_up", [KEY_BRACKETRIGHT])
	_action(&"game_speed_down", [KEY_BRACKETLEFT])

static func _action(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	# 0.2s dead zone keeps a keypress from registering twice on key repeat.
	InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
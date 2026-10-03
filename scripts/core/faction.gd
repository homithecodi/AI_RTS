class_name Faction
extends RefCounted

var team: int = Defs.TEAM_PLAYER
var is_ai: bool = false
var ore: float = Defs.START_ORE
var income_bonus: float = 1.0
var defeated: bool = false
var defeated_time: float = -1.0

var units: Array[Unit] = []
var buildings: Array[Building] = []

var power_produced: float = 0.0
var power_used: float = 0.0
var income_rate: float = 0.0

var damage_dealt: float = 0.0
var damage_taken: float = 0.0
var units_built: int = 0
var units_lost: int = 0

func can_afford(cost: float) -> bool:
	return ore >= cost

func spend(cost: float) -> bool:
	if ore < cost:
		return false
	ore -= cost
	return true

func power_ratio() -> float:
	if power_used <= 0.01:
		return 1.0
	return clampf(power_produced / power_used, 0.35, 1.0)

func is_low_power() -> bool:
	return power_used > power_produced + 0.01

func rebuild_power() -> void:
	var produced := 0.0
	var used := 0.0
	for b in buildings:
		if not b.active:
			continue
		var p := float(b.def.get("power", 0))
		if p > 0.0:
			produced += p
		else:
			used += -p
	power_produced = produced
	power_used = used

func tick_economy(delta: float) -> void:
	income_rate = 0.0
	for b in buildings:
		if b.active and b.def.has("gather_rate"):
			income_rate += b.income
	ore += income_rate * income_bonus * delta

func is_alive() -> bool:
	return not defeated
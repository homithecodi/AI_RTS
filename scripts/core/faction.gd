class_name Faction
extends RefCounted
# One side's complete state: who it owns, how rich it is, and how much power it has.
#
# Factions are plain RefCounted data holders with no scene presence. They outlive
# individual entities, so their unit and building lists are the game's canonical
# roster — GameWorld keeps its own spatial index alongside them.
#
# Power is the central constraint: producers and consumers are summed by
# rebuild_power(), and anything above capacity slows down or stops. See
# power_ratio() and is_low_power().

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

## Deduct ore if it is available. Callers that only want to test affordability
## should use can_afford() so the check and the spend cannot disagree.
func spend(cost: float) -> bool:
	if ore < cost:
		return false
	ore -= cost
	return true

## Speed multiplier applied to production and unit movement. Floored at 0.35 so a
## brownout is a penalty rather than a lockout.
func power_ratio() -> float:
	if power_used <= 0.01:
		return 1.0
	return clampf(power_produced / power_used, 0.35, 1.0)

## True when consumption exceeds generation. Structures keep working at reduced
## speed; only units and production queues feel the penalty.
func is_low_power() -> bool:
	return power_used > power_produced + 0.01

## Recalculate the power totals from the current building list. Called whenever the
## roster changes rather than every frame, since it is O(buildings).
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

## Bank the ore collected by every finished refinery this frame. income_bonus is how
## the AI's difficulty ramp is applied.
func tick_economy(delta: float) -> void:
	income_rate = 0.0
	for b in buildings:
		if b.active and b.def.has("gather_rate"):
			income_rate += b.income
	ore += income_rate * income_bonus * delta

func is_alive() -> bool:
	return not defeated
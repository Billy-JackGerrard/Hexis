## Advances one combat tick over the live sim state, per 04-combat.md: every
## squad and every Defensive building auto-attacks the best valid enemy in range
## (CombatTargeting), damage runs through the modifier/armor system (CombatMath),
## splash spreads to enemies around the impact hex, and the dead are pruned.
## Stateless/static, same split as ProductionManager (data on the instances,
## timing/rules here).
##
## Cadence model: each attacker banks dt * attackSpeed on its own
## attack_progress accumulator and fires one whole "volley" per unit banked,
## mirroring SquadInstance.edge_progress. A squad's volley is one attack per
## living member (all members share type/stats, so they fire in unison — a
## documented simplification of per-troop cooldowns); a Defensive building fires
## a single shot.
##
## Simplifications noted for later slices: an attack on a squad focus-fires its
## first living member (overflow past a kill is lost); splash hits one member
## per other enemy squad in radius (not every stacked member) and never friendly
## units. splashRadius is 1-indexed against the impact hex: 1 means every other
## enemy on the impact hex itself (no spread to neighbors), 2 adds the ring at
## distance 1, 3 the ring at distance 2, etc. — see _apply_attack's
## `splash_radius - 1` distance check.
##
## A non-HQ base building at 0 HP becomes a ruin (stays in base.buildings,
## non-functional) rather than being removed; an HQ at 0 HP instead flips its
## base to the attacker and respawns at full HP (see _prune_dead). Standalone
## buildings (Tower/Landmine — the only standalone types with combat HP; Road/
## Bridge/Dock have none, per BuildingStats.max_hp) are now targetable too and,
## per 06-building-stats-and-defenses.md, delete outright at 0 HP rather than
## ruining, unlike a base building. Walls are targetable too (edge-keyed, no
## single hex — see CombatTarget.distance_from/for_building) and, like
## standalone buildings, delete outright rather than ruining.
## Terrain defense bonuses and stealth/detection (hill defender bonus, forest
## ambush, Tower/Radar Array detector) are handled via CombatTarget's
## defense_multiplier/is_hidden/reveal_range (computed from `grid` at
## CombatTarget construction time) and the `detections` map DetectionSystem
## produces — see DetectionSystem for the hidden-state/detector rules
## themselves; this file only threads `grid`/`detections` through.
##
## Line attacks (Tank Obliterator's rail gun, `attacker_def.lineAttack`): an
## alternate AoE shape to splashRadius's circle-around-impact — a straight,
## 1-hex-wide beam from the attacker's own hex through the target's hex and
## onward to `range` hexes total, damaging every enemy squad it crosses
## (goes through troops) and stopping dead at the first hex carrying ANY
## building (friend or foe — a physical obstruction that blocks a beam the
## same way it wouldn't block a scattered splash), see _apply_line_attack.
##
## Status effects (freeze/stun/knockback/emp, StatusEffectSystem): a
## freeze/stun-locked attacker skips its turn entirely (no attack_progress
## banked, mirroring "can't move or attack"); a stun's trailing tail
## multiplies attackSpeed by StatusEffectSystem.attack_speed_mult(). A
## successful hit's statusEffectOnHit (if any) is rolled and applied to the
## PRIMARY target only via StatusEffectSystem.apply_on_hit() — splash victims
## never carry a status effect, see StatusEffectSystem's own scoping note.
##
## Auras (AuraSystem): a suppress_targeting-covered Defensive building skips
## its turn entirely (no attack_progress banked); attack_speed_mult multiplies
## in alongside the stun tail; damage_reduction reaches CombatMath via each
## CombatTarget's aura_damage_reduction_mult (set at build_targets time, same
## as defense_multiplier); heal_over_time/heal_out_of_combat apply as flat HP
## regen via AuraSystem.apply_heals() once per tick, before targeting/damage.
##
## Out-of-combat building regen (BuildingRegenSystem): runs after this tick's
## damage/prune step, per 06-building-stats-and-defenses.md's global
## 5%-max-HP-per-5-second-tick rule for any damaged-but-surviving building.
class_name CombatResolver
extends RefCounted

## squads: every player's live squads (mutated: dead members/squads pruned).
## bases: every player's bases (mutated: destroyed buildings pruned).
## troops_by_id: id -> TroopInstance registry (mutated: dead troops removed).
## standalone_buildings: every Engineer-placed standalone building (mutated:
## Tower/Landmine deleted outright at 0 HP — see _prune_dead; Road/Bridge/Dock
## carry no combat HP so they're never touched here).
## detections: owner_id -> {hex_key: true}, as produced by
## DetectionSystem.resolve_tick() (caller's responsibility, same as `grid`/
## the vision system's `visions` dict — not recomputed here).
## auras: {"squads": {...}, "buildings": {...}}, as produced by
## AuraSystem.resolve_tick() — same caller-computed-once convention.
## regiments: every live RegimentInstance (mutated: a regiment whose Commander
## squad died this tick is removed — see _prune_dead's
## _disband_regiments_for_dead_commanders).
## production_queues: building_id -> ProductionQueue (mutated: per
## 07-data-architecture.md 3b, a building ruined this tick has its own entry
## erased, and every building on a base captured this tick (HQ hits 0 HP) has
## its entry erased too — see _prune_dead).
static func resolve_tick(
	dt: float,
	squads: Array[SquadInstance],
	bases: Array[BaseInstance],
	troops_by_id: Dictionary,
	grid: HexGrid,
	troop_defs: Dictionary,
	building_defs: Dictionary,
	detections: Dictionary = {},
	auras: Dictionary = {},
	standalone_buildings: Array[BuildingInstance] = [],
	regiments: Array[RegimentInstance] = [],
	production_queues: Dictionary = {},
) -> void:
	StatusEffectSystem.resolve_tick(dt, squads, bases)
	AuraSystem.apply_heals(dt, auras, squads, troops_by_id, troop_defs)

	var targets := build_targets(squads, bases, troops_by_id, grid, troop_defs, building_defs, auras, standalone_buildings)

	for squad in squads:
		_advance_squad(squad, dt, targets, troops_by_id, troop_defs, grid, building_defs, detections, auras)

	for base in bases:
		for building in base.buildings:
			_advance_building(building, base.owner_id, dt, targets, troops_by_id, troop_defs, building_defs, grid, detections, auras)
	for building in standalone_buildings:
		_advance_building(building, building.owner_id, dt, targets, troops_by_id, troop_defs, building_defs, grid, detections, auras)

	_prune_dead(squads, bases, troops_by_id, grid, standalone_buildings, regiments, production_queues)
	BuildingRegenSystem.resolve_tick(dt, bases)

## Builds the CombatTarget view over every live squad and combat-tracked
## building (base-attached or standalone). Buildings with max_hp 0
## (infrastructure stubs, or defs carrying no HP — Road/Bridge/Dock) are not
## targetable. `grid` feeds each CombatTarget's terrain-derived
## defense_multiplier/is_hidden/reveal_range; `auras` feeds a squad's
## damage_reduction-derived aura_damage_reduction_mult.
static func build_targets(squads: Array[SquadInstance], bases: Array[BaseInstance], troops_by_id: Dictionary, grid: HexGrid, troop_defs: Dictionary, building_defs: Dictionary, auras: Dictionary = {}, standalone_buildings: Array[BuildingInstance] = []) -> Array[CombatTarget]:
	var targets: Array[CombatTarget] = []
	for squad in squads:
		# A boarded/docked squad has no independent position and is hidden
		# inside its carrier/building — not a legal target, same as it can't
		# fire back (see _advance_squad's matching skip).
		if squad.member_ids.is_empty() or squad.is_docked():
			continue
		targets.append(CombatTarget.for_squad(squad, troop_defs.get(squad.troop_type, {}), troops_by_id, grid, auras))
	for base in bases:
		for building in base.buildings:
			if building.max_hp <= 0.0:
				continue
			var target := CombatTarget.for_building(building, building_defs.get(building.building_type, {}), building_defs, grid)
			target.owner_id = base.owner_id
			targets.append(target)
	for building in standalone_buildings:
		if building.max_hp <= 0.0:
			continue
		var target := CombatTarget.for_building(building, building_defs.get(building.building_type, {}), building_defs, grid)
		target.owner_id = building.owner_id
		targets.append(target)
	return targets

static func _advance_squad(squad: SquadInstance, dt: float, targets: Array[CombatTarget], troops_by_id: Dictionary, troop_defs: Dictionary, grid: HexGrid, building_defs: Dictionary, detections: Dictionary = {}, auras: Dictionary = {}) -> void:
	if squad.member_ids.is_empty():
		return
	# A boarded/docked squad can't fire — it has no independent position to
	# fire from and isn't even in `targets` for CombatTargeting to react to.
	if squad.is_docked():
		return
	squad.reveal_cooldown_remaining = max(0.0, squad.reveal_cooldown_remaining - dt)
	# A freeze/stun full lockout means this squad can't move OR attack — skip
	# its turn entirely, banking no attack_progress (per 05-troop-stat-schema.md).
	if StatusEffectSystem.is_locked_out(squad):
		return
	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	var attack_speed := float(def.get("attackSpeed", 0.0)) * StatusEffectSystem.attack_speed_mult(squad) * AuraSystem.attack_speed_mult(auras, squad.id)
	# Non-combatants (Engineer/Glider — empty canTarget) and unarmed carriers
	# never fire.
	if attack_speed <= 0.0 or def.get("canTarget", []).is_empty():
		return

	squad.attack_progress += dt * attack_speed
	# Ready-but-idle: hold at most one banked volley so a unit fires promptly
	# when an enemy arrives, without stockpiling charge over a long lull.
	if CombatTargeting.select_target(squad, def, targets, detections, grid) == null:
		squad.attack_progress = min(squad.attack_progress, 1.0)
		return

	var base_damage := float(def.get("damage", 0.0))
	var splash := int(def.get("splashRadius", 0))
	while squad.attack_progress >= 1.0:
		var target := CombatTargeting.select_target(squad, def, targets, detections, grid)
		if target == null:
			break
		for member_id in _living_members(squad, troops_by_id):
			_apply_attack(def, base_damage, squad.owner_id, squad.current_hex, target, targets, troops_by_id, splash, troop_defs, building_defs, grid)
		squad.attack_progress -= 1.0
		# Attacking breaks this squad's own stealth/ambush (revealsOnAttack /
		# "hidden until engaging") for a cooldown, per DetectionSystem.
		squad.reveal_cooldown_remaining = DetectionSystem.REVEAL_COOLDOWN_SECONDS

static func _advance_building(building: BuildingInstance, owner_id: String, dt: float, targets: Array[CombatTarget], troops_by_id: Dictionary, troop_defs: Dictionary, building_defs: Dictionary, grid: HexGrid, detections: Dictionary = {}, auras: Dictionary = {}) -> void:
	if building.max_hp > 0.0 and building.current_hp <= 0.0:
		return
	# A frozen/stunned Defensive building can't fire back either, nor can one
	# under an enemy Disruptor's suppress_targeting aura.
	if StatusEffectSystem.is_locked_out(building) or AuraSystem.is_suppressed(auras, building.id):
		return
	var stats := BuildingStats.defensive_stats(building_defs.get(building.building_type, {}), building.level, building.material, building_defs)
	if stats.is_empty():
		return
	var attack_speed := float(stats.get("attackSpeed", 0.0)) * StatusEffectSystem.attack_speed_mult(building)
	# attackSpeed omitted/0 with selfDestructOnTrigger = a one-shot trap
	# (Landmine): no accumulator, it fires the instant a valid enemy is in
	# range and is destroyed by its own blast — see _trigger_self_destruct.
	if attack_speed <= 0.0 and stats.get("selfDestructOnTrigger", false):
		_trigger_self_destruct(building, owner_id, stats, targets, troops_by_id, troop_defs, building_defs, grid, detections)
		return
	if attack_speed <= 0.0 or stats.get("canTarget", []).is_empty():
		return

	var attacker_range := int(stats.get("range", 0))
	var base_damage := float(stats.get("damage", 0.0))
	var splash := int(stats.get("splashRadius", 0))
	# Wood Tower fires one independent accumulator per turret (BuildingStats.
	# turret_count via BuildingInstance.turret_progress) instead of the usual
	# single one — every other Defensive building has exactly one entry here,
	# so this loop is a no-op wrapper around the old single-shot behaviour.
	# `claimed_this_tick` steers each later turret away from a target an
	# earlier turret already picked this tick (see select_auto's exclude_ids),
	# so a multi-turret tower spreads across separate enemies.
	var claimed_this_tick: Dictionary = {}
	for i in building.turret_progress.size():
		building.turret_progress[i] += dt * attack_speed
		while building.turret_progress[i] >= 1.0:
			var target := CombatTargeting.select_auto(building.hex, owner_id, attacker_range, stats, targets, detections, grid, claimed_this_tick)
			if target == null:
				building.turret_progress[i] = min(building.turret_progress[i], 1.0)
				break
			_apply_attack(stats, base_damage, owner_id, building.hex, target, targets, troops_by_id, splash, troop_defs, building_defs, grid)
			claimed_this_tick[target.target_id()] = true
			building.turret_progress[i] -= 1.0

## A selfDestructOnTrigger building (Landmine) has no attackSpeed to bank
## against — it fires at most once, the instant a valid enemy comes into
## range, dealing full damage + splash exactly like a normal attack, then
## zeroes its own HP so _prune_dead deletes it outright this same tick
## (standalone buildings never ruin, per 06-building-stats-and-defenses.md —
## matches the data notes' "deals its damage ... and is destroyed
## immediately" rather than persisting as a repeating attacker).
static func _trigger_self_destruct(building: BuildingInstance, owner_id: String, stats: Dictionary, targets: Array[CombatTarget], troops_by_id: Dictionary, troop_defs: Dictionary, building_defs: Dictionary, grid: HexGrid, detections: Dictionary) -> void:
	if stats.get("canTarget", []).is_empty():
		return
	var attacker_range := int(stats.get("range", 0))
	var target := CombatTargeting.select_auto(building.hex, owner_id, attacker_range, stats, targets, detections, grid)
	if target == null:
		return
	var base_damage := float(stats.get("damage", 0.0))
	var splash := int(stats.get("splashRadius", 0))
	_apply_attack(stats, base_damage, owner_id, building.hex, target, targets, troops_by_id, splash, troop_defs, building_defs, grid)
	building.current_hp = 0.0

## One attack: either a line-attack beam (attacker_def.lineAttack — see
## _apply_line_attack) OR the usual full damage to the primary target plus the
## same computed damage to every OTHER enemy target within `splash_radius - 1`
## hexes of the impact hex (splashRadius is 1-indexed: 1 = impact hex only, 2
## = impact hex + 1 ring out, etc.). Either way, the attacker's statusEffectOnHit (if any) is
## then rolled and applied to the PRIMARY target only — see StatusEffectSystem's
## scoping note on splash (a line attack's extra victims are scoped the same
## way splash's are: damage only, never a status effect).
static func _apply_attack(attacker_def: Dictionary, base_damage: float, attacker_owner: String, attacker_hex: HexCoord, target: CombatTarget, targets: Array[CombatTarget], troops_by_id: Dictionary, splash_radius: int, troop_defs: Dictionary, building_defs: Dictionary, grid: HexGrid) -> void:
	if attacker_def.get("lineAttack", false):
		_apply_line_attack(attacker_def, base_damage, attacker_owner, attacker_hex, target, targets, troops_by_id)
	else:
		_damage_target(target, CombatMath.resolve_damage(attacker_def, base_damage, target), attacker_owner, troops_by_id)
		if splash_radius > 0:
			for other in targets:
				if other == target or other.owner_id == attacker_owner or not other.is_alive():
					continue
				if HexCoord.distance(target.hex, other.hex) <= splash_radius - 1:
					_damage_target(other, CombatMath.resolve_damage(attacker_def, base_damage, other), attacker_owner, troops_by_id)

	var status_effect: Dictionary = attacker_def.get("statusEffectOnHit", {})
	if not status_effect.is_empty() and target.is_alive():
		var target_def: Dictionary = troop_defs.get(target.squad.troop_type, {}) if target.kind == CombatTarget.Kind.SQUAD else building_defs.get(target.building.building_type, {})
		StatusEffectSystem.apply_on_hit(status_effect, target, target_def, attacker_hex, grid)

## Tank Obliterator's rail gun: fires along `_beam_hexes` (attacker's hex
## through the target's hex, out to `attacker_def.range` hexes total) and
## damages every enemy squad standing on a beam hex — goes through troops,
## no per-target falloff. The first beam hex carrying ANY building (checked
## by hex equality against every target this tick, so several stacked things
## on one hex all resolve together) is a hard stop: an enemy building there
## takes the hit like any other victim, a friendly one just blocks silently
## (never friendly fire, same rule splash already follows) — either way the
## beam goes no further. A Wall has no single hex of its own (edge-based,
## hex_b set) so it's excluded from this hex-equality check entirely and never
## blocks a beam.
static func _apply_line_attack(attacker_def: Dictionary, base_damage: float, attacker_owner: String, attacker_hex: HexCoord, target: CombatTarget, targets: Array[CombatTarget], troops_by_id: Dictionary) -> void:
	var beam := _beam_hexes(attacker_hex, target.hex, int(attacker_def.get("range", 0)))
	for hex in beam:
		var blocked := false
		for other in targets:
			if not other.is_alive() or other.hex == null or other.hex_b != null or not other.hex.equals(hex):
				continue
			if other.kind == CombatTarget.Kind.BUILDING:
				blocked = true
				if other.owner_id == attacker_owner:
					continue
			elif other.owner_id == attacker_owner:
				continue
			_damage_target(other, CombatMath.resolve_damage(attacker_def, base_damage, other), attacker_owner, troops_by_id)
		if blocked:
			break

## The hex path a beam attack travels, in order outward from (but excluding)
## the attacker's own hex: the straight line to the target (HexCoord.line),
## extended past it in the same direction — HexCoord.direction_away, the same
## "away from attacker" approximation knockback already uses for an arbitrary
## hex pair — if `length` calls for more hexes than that leg covers, capped at
## `length` total either way.
static func _beam_hexes(attacker_hex: HexCoord, target_hex: HexCoord, length: int) -> Array[HexCoord]:
	var hexes := HexCoord.line(attacker_hex, target_hex)
	hexes.remove_at(0)
	if hexes.size() > length:
		hexes = hexes.slice(0, length)
	elif hexes.size() < length:
		var dir := HexCoord.direction_away(attacker_hex, target_hex)
		var last := target_hex
		while hexes.size() < length:
			last = HexCoord.neighbor(last, dir)
			hexes.append(last)
	return hexes

## Applies damage: buildings lose current_hp (and remember who hit them last,
## for HQ capture-flip attribution, plus reset their out-of-combat regen
## clock); a squad's first living member takes the hit (focus-fire).
static func _damage_target(target: CombatTarget, damage: float, attacker_owner: String, troops_by_id: Dictionary) -> void:
	if target.kind == CombatTarget.Kind.BUILDING:
		target.building.current_hp -= damage
		target.building.last_damaged_by = attacker_owner
		target.building.time_since_damage = 0.0
		target.building.regen_progress = 0.0
		return
	target.squad.time_since_damage = 0.0
	for member_id in target.squad.member_ids:
		var troop: TroopInstance = troops_by_id.get(member_id)
		if troop != null and troop.current_hp > 0.0:
			troop.current_hp -= damage
			return

static func _living_members(squad: SquadInstance, troops_by_id: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for member_id in squad.member_ids:
		var troop: TroopInstance = troops_by_id.get(member_id)
		if troop != null and troop.current_hp > 0.0:
			result.append(member_id)
	return result

## Removes dead troops from their squads and the registry, disbands emptied
## squads (taking any boarded cargo down with a destroyed carrier, or any
## docked squad down with a destroyed building — see 04-combat.md's Cargo
## section), deletes destroyed non-Wall buildings from
## their bases (or ruins them), deletes a destroyed Wall or standalone
## building (Tower/Landmine) outright — neither ever ruins, per
## 06-building-stats-and-defenses.md's Destruction & Ruins section — clearing
## `grid.set_wall()` so a destroyed Wall's edge reopens for movement, and
## disbands any regiment whose Commander squad died this tick (see
## _disband_regiments_for_dead_commanders), and clears production_queues per
## 07-data-architecture.md 3b: a freshly-ruined building's own queue entry is
## erased, and a captured base (HQ hits 0 HP) erases every one of its
## buildings' queue entries — in both cases the in-progress entry and its
## already-spent resources are lost, not refunded/carried over.
static func _prune_dead(squads: Array[SquadInstance], bases: Array[BaseInstance], troops_by_id: Dictionary, grid: HexGrid, standalone_buildings: Array[BuildingInstance] = [], regiments: Array[RegimentInstance] = [], production_queues: Dictionary = {}) -> void:
	for squad in squads:
		var survivors: Array[String] = []
		for member_id in squad.member_ids:
			var troop: TroopInstance = troops_by_id.get(member_id)
			if troop != null and troop.current_hp > 0.0:
				survivors.append(member_id)
			else:
				troops_by_id.erase(member_id)
		squad.member_ids = survivors

	# A carrier squad about to be pruned (no living members) takes every
	# boarded squad's members with it — cargo does not survive the loss of
	# its carrier, and there's no "spills out" recovery.
	var doomed_cargo_ids: Dictionary = {}
	for squad in squads:
		if squad.member_ids.is_empty() and not squad.cargo_squad_ids.is_empty():
			for cargo_id in squad.cargo_squad_ids:
				doomed_cargo_ids[cargo_id] = true
			squad.cargo_squad_ids = []

	# Same rule for a building (Hangar) that just hit 0 HP: every squad docked
	# inside it dies too — no "spills out" recovery here either.
	for base in bases:
		for building in base.buildings:
			if building.max_hp > 0.0 and building.current_hp <= 0.0 and not building.docked_squad_ids.is_empty():
				for docked_id in building.docked_squad_ids:
					doomed_cargo_ids[docked_id] = true
				building.docked_squad_ids = []
	for building in standalone_buildings:
		if building.max_hp > 0.0 and building.current_hp <= 0.0 and not building.docked_squad_ids.is_empty():
			for docked_id in building.docked_squad_ids:
				doomed_cargo_ids[docked_id] = true
			building.docked_squad_ids = []

	if not doomed_cargo_ids.is_empty():
		for squad in squads:
			if doomed_cargo_ids.has(squad.id):
				for member_id in squad.member_ids:
					troops_by_id.erase(member_id)
				squad.member_ids = []

	for i in range(squads.size() - 1, -1, -1):
		if squads[i].member_ids.is_empty():
			squads.remove_at(i)

	_disband_regiments_for_dead_commanders(squads, regiments)

	for base in bases:
		for i in range(base.buildings.size() - 1, -1, -1):
			var building := base.buildings[i]
			if building.max_hp <= 0.0 or building.current_hp > 0.0:
				continue
			if building.building_type == "hq":
				# Capture, per 02-bases-and-buildings.md: ownership of the whole
				# base flips to whoever dealt the killing blow (buildings derive
				# ownership from base.owner_id, so flipping it here is enough —
				# no per-building ownership to update), and the HQ respawns
				# immediately at full HP under its new owner. It's never ruined
				# or removed. Garrisoned squads keep their own owner_id and are
				# untouched (elimination-on-last-base is a separate, not-yet-
				# built system).
				if building.last_damaged_by != "" and building.last_damaged_by != base.owner_id:
					base.owner_id = building.last_damaged_by
					for captured_building in base.buildings:
						production_queues.erase(captured_building.id)
				building.current_hp = building.max_hp
				building.last_damaged_by = ""
				building.time_since_damage = 0.0
				building.regen_progress = 0.0
			elif building.building_type == "wall":
				# A Wall never ruins — it deletes outright, freeing its edge
				# for a fresh build at normal cost, per 06-building-stats-and-
				# defenses.md's Destruction & Ruins section (same treatment as
				# a standalone building). Clearing grid.set_wall() reopens the
				# edge for movement/pathing immediately.
				grid.set_wall(building.hex_a, building.hex_b, false)
				base.buildings.remove_at(i)
			else:
				# Non-HQ, non-Wall buildings become a rebuildable ruin instead
				# of vanishing: the hex/adjacency slot stays occupied but the
				# building no longer functions (every consuming system already
				# gates on current_hp <= 0).
				building.is_ruin = true
				production_queues.erase(building.id)

	for i in range(standalone_buildings.size() - 1, -1, -1):
		if standalone_buildings[i].max_hp > 0.0 and standalone_buildings[i].current_hp <= 0.0:
			standalone_buildings.remove_at(i)

## Per 04-combat.md: "if a Commander dies mid-battle, its regiment disbands —
## every member squad reverts to operating independently (no more shared
## rally point, no more buff aura)." Called after squads are pruned above, so
## a regiment whose commander_id no longer names a living squad in `squads`
## is disbanded: every member squad's commander_id is cleared, and a squad
## still mid-lock-step (`order.type == "regiment_move"`) is reset to idle
## (`{}`) rather than left referencing a regiment that no longer exists —
## same "revert to independent" treatment an ad hoc-split member already gets
## once its own path drains (see MovementResolver's regiment section), just
## triggered by the Commander's death instead of a manual leave_regiment
## order. The regiment itself is then removed from `regiments`.
static func _disband_regiments_for_dead_commanders(squads: Array[SquadInstance], regiments: Array[RegimentInstance]) -> void:
	if regiments.is_empty():
		return
	var living_ids: Dictionary = {}
	for squad in squads:
		living_ids[squad.id] = true

	for i in range(regiments.size() - 1, -1, -1):
		var regiment := regiments[i]
		if living_ids.has(regiment.commander_id):
			continue
		for squad in squads:
			if regiment.squad_ids.has(squad.id):
				squad.commander_id = ""
				if squad.order.get("type", "") == "regiment_move":
					squad.order = {}
		regiments.remove_at(i)

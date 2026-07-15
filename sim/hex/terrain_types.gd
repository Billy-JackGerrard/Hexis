## Terrain and domain constants, and the movement-cost table between them.
##
## Source of truth: game-design/01-map-and-terrain.md's terrain table.
## INF means "impassable for this domain on this terrain unless a
## Road/Bridge is present (Forest/River) or the unit has a matching
## terrainOverrides flag (05-troop-stat-schema.md)".
class_name Terrain
extends RefCounted

enum Type { PLAINS, FOREST, HILLS, RIVER, OCEAN }
enum Domain { INFANTRY, LAND, AIR, NAVAL }

## Road/Bridge are hex-keyed standalone buildings (see
## game-design/07-data-architecture.md's Standalone Buildings section) that
## clear a specific terrain block on the hex they're built on — distinct from
## Walls, which block a hex *edge* regardless of terrain.
enum Infrastructure { NONE, ROAD, BRIDGE }

const INF: float = -1.0 ## sentinel for "impassable", not a numeric cost

## Placeholder — the design docs establish Hills slow Infantry but never pin
## an exact multiplier. Tune freely; nothing else depends on this number yet.
const HILLS_INFANTRY_COST: float = 2.0

## Placeholder — a troop/building standing on Forest sees at half its base
## visionRange (Forest obscures a unit's own sightline the same way it hides
## the unit itself for ambush — see DetectionSystem.is_squad_hidden).
const FOREST_VISION_MULTIPLIER: float = 0.5

## Hills obstruct sight the same way Forest does (elevation blocks line of
## sight, it doesn't extend it) — a troop/building standing on Hills also
## sees at half its base visionRange.
const HILLS_VISION_MULTIPLIER: float = 0.5

## Placeholder — how much vision range a sightline loses per Forest hex it
## crosses en route to its target, even when neither viewer nor target is
## itself standing in that Forest (01-map-and-terrain.md's "Forests are where
## sneaky plays happen" extended to blocking sight through them, not just
## hiding whatever's inside). Mirrors FOREST_VISION_MULTIPLIER's own-tile
## penalty but applies per intervening hex instead of a flat halving.
const FOREST_LOS_RANGE_PENALTY_PER_HEX: float = 1.0

## Mirrors FOREST_LOS_RANGE_PENALTY_PER_HEX — a Hills hex crossed en route
## blocks sight through it just like Forest does.
const HILLS_LOS_RANGE_PENALTY_PER_HEX: float = 1.0

## Placeholder — 04-combat.md establishes "Hills give a defender bonus to
## troops stationed there" but never pins an exact multiplier. A received-
## damage multiplier <1.0, composed the same multiplicative way as
## CombatMath's other received-side modifiers. Tune freely; nothing else
## depends on this number yet.
const HILLS_DEFENDER_BONUS: float = 0.75

## cost[terrain][domain] -> hexes-per-second divisor (>1 = slower, INF = blocked).
## Air ignores all terrain restrictions and is always 1.0.
const COST := {
	Type.PLAINS: {
		Domain.INFANTRY: 1.0, Domain.LAND: 1.0, Domain.AIR: 1.0, Domain.NAVAL: INF,
	},
	Type.FOREST: {
		Domain.INFANTRY: 1.0, Domain.LAND: INF, Domain.AIR: 1.0, Domain.NAVAL: INF,
	},
	Type.HILLS: {
		Domain.INFANTRY: HILLS_INFANTRY_COST, Domain.LAND: 1.0, Domain.AIR: 1.0, Domain.NAVAL: INF,
	},
	Type.RIVER: {
		Domain.INFANTRY: INF, Domain.LAND: INF, Domain.AIR: 1.0, Domain.NAVAL: 1.0,
	},
	Type.OCEAN: {
		Domain.INFANTRY: INF, Domain.LAND: INF, Domain.AIR: 1.0, Domain.NAVAL: 1.0,
	},
}

## Whether this terrain is buildable at all (Plains only, per the table —
## the Treehouse/Windy Peaks Forest/Hill exceptions are per-building overrides
## handled by placement rules elsewhere, not a blanket terrain flag here).
static func is_buildable(terrain: Type) -> bool:
	return terrain == Type.PLAINS

## Base movement cost for a domain crossing a terrain, before any per-unit
## terrainOverrides (ignoresForestBlock, etc. — see 05-troop-stat-schema.md)
## are applied by the caller. Air always returns 1.0 regardless of terrain.
static func cost(terrain: Type, domain: Domain) -> float:
	if domain == Domain.AIR:
		return 1.0
	return COST[terrain][domain]

static func is_passable(terrain: Type, domain: Domain) -> bool:
	return cost(terrain, domain) != INF

## Movement cost accounting for hex-level infrastructure (see 01-map-and-terrain.md's
## "Forest ... Blocked unless a Road is built through it" / "River ... Blocked unless
## a Bridge is built"): a Road clears Forest's Land block, a Bridge clears River's
## Infantry/Land block. Infrastructure that doesn't apply to the terrain/domain in
## question (e.g. a Bridge on a Forest hex) is simply a no-op — falls back to `cost()`.
## `overrides` is a troop def's `terrainOverrides` dict (05-troop-stat-schema.md):
## `ignoresForestBlock`/`ignoresRiverBlock` clear the same blocks a Road/Bridge would,
## per-unit rather than per-hex. Never clears a Wall — that's a separate edge check.
static func effective_cost(terrain: Type, domain: Domain, infrastructure: Infrastructure = Infrastructure.NONE, overrides: Dictionary = {}) -> float:
	var base := cost(terrain, domain)
	if base != INF:
		return base
	if infrastructure == Infrastructure.ROAD and terrain == Type.FOREST and domain == Domain.LAND:
		return 1.0
	if infrastructure == Infrastructure.BRIDGE and terrain == Type.RIVER and (domain == Domain.INFANTRY or domain == Domain.LAND):
		return 1.0
	if overrides.get("ignoresForestBlock", false) and terrain == Type.FOREST and domain == Domain.LAND:
		return 1.0
	if overrides.get("ignoresRiverBlock", false) and terrain == Type.RIVER and (domain == Domain.INFANTRY or domain == Domain.LAND):
		return 1.0
	return INF

static func is_passable_with(terrain: Type, domain: Domain, infrastructure: Infrastructure = Infrastructure.NONE) -> bool:
	return effective_cost(terrain, domain, infrastructure) != INF

## Multiplier applied to a unit/building's own base visionRange for standing
## on this terrain — Forest and Hills both halve it (elevation/foliage block
## sight, they don't extend it); every other terrain leaves it as-is.
## `exempt` (a Terrain.Type, or -1 for none) skips the penalty for that one
## terrain — a Treehouse/Windy Peaks building built into Forest/Hills rather
## than merely standing on it.
static func vision_multiplier(terrain: Type, exempt: int = -1) -> float:
	if terrain == exempt:
		return 1.0
	match terrain:
		Type.FOREST:
			return FOREST_VISION_MULTIPLIER
		Type.HILLS:
			return HILLS_VISION_MULTIPLIER
		_:
			return 1.0

## Received-damage multiplier for standing on this terrain — Hills give
## defenders a flat damage-reduction bonus (04-combat.md); every other
## terrain grants none.
static func defense_bonus(terrain: Type) -> float:
	return HILLS_DEFENDER_BONUS if terrain == Type.HILLS else 1.0

## Maps a troop def's `domain` string (schema enum "Infantry"/"Land"/"Air"/"Naval")
## to this module's Domain enum — a direct 1:1 name match. Defaults to INFANTRY (with
## an error) on an unrecognized string rather than failing silently.
static func domain_from_string(name: String) -> Domain:
	match name:
		"Infantry":
			return Domain.INFANTRY
		"Land":
			return Domain.LAND
		"Air":
			return Domain.AIR
		"Naval":
			return Domain.NAVAL
		_:
			push_error("Terrain.domain_from_string: unrecognized domain '%s', defaulting to Infantry" % name)
			return Domain.INFANTRY

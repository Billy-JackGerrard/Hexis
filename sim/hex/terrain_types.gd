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

## Height difference (in HexGrid elevation levels) at which an upward step
## stops being a climbable slope and becomes a sheer cliff face — impassable
## to Infantry and Land outright, no Road/override clears it. Naval never
## meets one (water is always lowland) and Air ignores elevation entirely.
## Set to 2 so a single-level step is always a slope and only a double step
## walls off: the worldgen pass (TerrainGenerator.generate_elevation) leans on
## exactly that to carve plateaus that are cliff-faced on some edges and
## ramped on others.
const CLIFF_ELEVATION_DELTA: int = 2

## Extra movement cost added per elevation level *gained* by a step, on top of
## the destination terrain's own cost. Descending and level ground add nothing
## — never a discount, since HexGrid.find_path's heuristic assumes a minimum
## step cost of 1.0 and would stop being admissible below it.
const SLOPE_ASCENT_COST_PER_LEVEL: float = 1.0

## Placeholder — a troop/building standing on Forest sees at half its base
## visionRange (Forest obscures a unit's own sightline the same way it hides
## the unit itself for ambush — see DetectionSystem.is_squad_hidden).
const FOREST_VISION_MULTIPLIER: float = 0.5

## Vision range added per elevation level a viewer is standing on. Hills no
## longer *reduce* the viewer's own sight (the pre-elevation model, where
## Hills were treated as foliage-equivalent because there was no height axis
## to reason with); with real elevation, standing higher extends how far you
## see and lets your sightline clear obstacles below you — see
## VisionSystem._is_elevation_blocked. Hills' *concealment* role is unchanged:
## they still block sight for anyone trying to look past/through them from
## lower ground, which is now a consequence of the height itself rather than a
## flat per-hex range penalty.
const ELEVATION_VISION_BONUS_PER_LEVEL: float = 1.5

## Effective sightline height of a viewer/target standing on a hex, above that
## hex's own ground level — the "eye height" the elevation silhouette test
## interpolates between. Keeping it at one full elevation level means two
## units on flat ground can always see each other over flat ground in between.
const EYE_HEIGHT: float = 1.0

## How far a Forest hex's canopy rises above its own ground level for the
## silhouette test. Equal to EYE_HEIGHT so forest on level ground never hard-
## blocks by itself (the additive FOREST_LOS_RANGE_PENALTY_PER_HEX below is
## what makes forest degrade sight); it only closes a sightline when the
## forest also sits higher than both viewer and target.
const FOREST_CANOPY_HEIGHT: float = 1.0

## Placeholder — how much vision range a sightline loses per Forest hex it
## crosses en route to its target, even when neither viewer nor target is
## itself standing in that Forest (01-map-and-terrain.md's "Forests are where
## sneaky plays happen" extended to blocking sight through them, not just
## hiding whatever's inside). Mirrors FOREST_VISION_MULTIPLIER's own-tile
## penalty but applies per intervening hex instead of a flat halving.
const FOREST_LOS_RANGE_PENALTY_PER_HEX: float = 1.0

## Hills deliberately have NO equivalent of FOREST_LOS_RANGE_PENALTY_PER_HEX.
## A Hills hex crossed en route obstructs sight because it is physically
## taller than the sightline passing over it (VisionSystem._is_elevation_
## blocked), not because of a flat per-hex range subtraction — the two would
## double-count, and only the geometric one gets the direction right (a viewer
## on the same ridge should see straight along it, which a flat penalty
## punished exactly as hard as looking up at it from the valley floor).

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
##
## `bridge_material` (the placed Bridge's own BuildingInstance.material, "wood" or
## "stone" — see HexGrid.get_infrastructure_material) and `is_heavy_land` (true iff
## a Land-domain mover's troop def carries the "Heavy" tag, per 05-troop-stat-schema.md
## — see 08-troop-roster.md for the roster's Light/Heavy split) together gate a Wood
## Bridge against Heavy vehicles: too light to bear them, per 01-map-and-terrain.md.
## Infantry and a Stone Bridge are unaffected regardless of weight class.
static func effective_cost(terrain: Type, domain: Domain, infrastructure: Infrastructure = Infrastructure.NONE, overrides: Dictionary = {}, bridge_material: String = "", is_heavy_land: bool = false) -> float:
	var base := cost(terrain, domain)
	if base != INF:
		return base
	if infrastructure == Infrastructure.ROAD and terrain == Type.FOREST and domain == Domain.LAND:
		return 1.0
	if infrastructure == Infrastructure.BRIDGE and terrain == Type.RIVER and (domain == Domain.INFANTRY or domain == Domain.LAND):
		if domain == Domain.LAND and is_heavy_land and bridge_material == "wood":
			return INF
		return 1.0
	if overrides.get("ignoresForestBlock", false) and terrain == Type.FOREST and domain == Domain.LAND:
		return 1.0
	if overrides.get("ignoresRiverBlock", false) and terrain == Type.RIVER and (domain == Domain.INFANTRY or domain == Domain.LAND):
		return 1.0
	return INF

static func is_passable_with(terrain: Type, domain: Domain, infrastructure: Infrastructure = Infrastructure.NONE, bridge_material: String = "", is_heavy_land: bool = false) -> bool:
	return effective_cost(terrain, domain, infrastructure, {}, bridge_material, is_heavy_land) != INF

## Multiplier applied to a unit/building's own base visionRange for standing
## on this terrain — only Forest halves it (foliage in your face obscures your
## own sightline). Hills no longer carry a penalty here: height is a separate
## axis now, and standing on it *helps* you see (elevation_vision_bonus).
## `exempt` (a Terrain.Type, or -1 for none) skips the penalty for that one
## terrain — a Treehouse building built into the canopy rather than merely
## standing under it.
static func vision_multiplier(terrain: Type, exempt: int = -1) -> float:
	if terrain == exempt:
		return 1.0
	match terrain:
		Type.FOREST:
			return FOREST_VISION_MULTIPLIER
		_:
			return 1.0

## Flat vision range added for standing `elevation` levels above lowland —
## applied after vision_multiplier, so it's a genuine bonus rather than
## something a Forest halving could scale away.
static func elevation_vision_bonus(elevation: int) -> float:
	return max(elevation, 0) * ELEVATION_VISION_BONUS_PER_LEVEL

## Height of a viewer's/target's eye line above sea level when standing on a
## hex at `elevation` — the endpoints the silhouette test interpolates between.
static func sightline_height(elevation: int) -> float:
	return float(elevation) + EYE_HEIGHT

## Height of the terrain itself at a hex, as an obstacle: its ground level plus
## whatever grows on it. Compared against the interpolated sightline to decide
## whether the hex silhouettes against (and so blocks) a line of sight.
static func obstacle_height(terrain: Type, elevation: int) -> float:
	var h := float(elevation)
	if terrain == Type.FOREST:
		h += FOREST_CANOPY_HEIGHT
	return h

## Extra movement cost for a single step from elevation `from_level` to
## `to_level`, or INF if the step is a cliff face this domain can't scale.
## Air flies over everything and Naval only ever moves across lowland water,
## so both are exempt. Descending or staying level is free — see
## SLOPE_ASCENT_COST_PER_LEVEL for why this never returns a negative.
static func elevation_step_cost(from_level: int, to_level: int, domain: Domain) -> float:
	if domain == Domain.AIR or domain == Domain.NAVAL:
		return 0.0
	var delta := to_level - from_level
	if delta >= CLIFF_ELEVATION_DELTA:
		return INF
	if delta <= 0:
		return 0.0
	return float(delta) * SLOPE_ASCENT_COST_PER_LEVEL

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

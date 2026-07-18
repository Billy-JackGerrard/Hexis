## Building.building_type -> 3D mesh judgment-call mapping for
## client/buildings/building_view_3d.gd. The asset pack (assets/buildings/)
## ships ~24 distinct building models per owner color plus a shared
## "neutral" set (walls/bridges/scaffolding/a few generic props) — nowhere
## near one dedicated mesh per one of this game's ~40 building_type ids, so
## most entries here deliberately reuse the closest thematic mesh (grouped
## by flavor below) rather than inventing new art. Every mapping is a
## judgment call, expected to be revisited once real per-building art
## exists — see game-design/10-tech-stack-and-build-order.md's Art section.
class_name BuildingMeshDefs
extends RefCounted

const BUILDINGS_DIR := "res://assets/buildings/"
const PROPS_DIR := "res://assets/decoration/props/"

## client/main.gd's OWNER_COLOR_PALETTE order (index 0-3) mapped to this
## pack's 4 owner-color folders; "p0".."p3" are the only owner_ids that ever
## appear (NetManager.MAX_PLAYERS is capped to 4 to match). Anything else —
## including "neutral", used for both unconquered Unique bases and
## barbarian outposts (see sim/worldgen/base_site_selector.gd's
## NEUTRAL_OWNER_ID) — falls back to the neutral/ folder.
const OWNER_ID_TO_FOLDER := {
	"p0": "blue", "p1": "red", "p2": "green", "p3": "yellow",
}

static func color_folder_for(owner_id: String) -> String:
	return OWNER_ID_TO_FOLDER.get(owner_id, "neutral")

## One RGB multiply tint (Color.WHITE = none) applied on top of whatever
## mesh gets picked, for building_types that reuse a mesh sculpted for a
## different building but need a color cue to read as their own element
## (frost/blaze/emp/etc.) — same multiply-not-replace technique as terrain
## decoration (see client/render_util.gd).
const ELEMENT_TINTS := {
	"cold_turret": Color(0.55, 0.85, 1.0),
	"ice_spire": Color(0.55, 0.85, 1.0),
	"frostworks": Color(0.55, 0.85, 1.0),
	"emp_turret": Color(0.75, 0.55, 1.0),
	"flame_turret": Color(1.0, 0.55, 0.3),
	"blazeworks": Color(1.0, 0.55, 0.3),
	"water_turret": Color(0.5, 0.75, 1.0),
	"missile_launcher": Color(0.55, 0.55, 0.6),
	"oil_rig": Color(0.35, 0.3, 0.25),
}

## Barbarian outposts / unconquered Unique bases are owner_id "neutral" (see
## sim/worldgen/base_site_selector.gd's NEUTRAL_OWNER_ID) but this pack's
## neutral/ folder only has bridges/walls/fences/scaffolding/a couple of
## generic props — not the full building roster. Neutral-owned buildings
## borrow one of the 4 real color folders for art instead, picked
## deterministically per building_type (not owner) so every barbarian Tower
## looks the same as every other, desaturated via NEUTRAL_TINT (applied by
## the caller, building_view_3d.gd) so it still reads as unclaimed rather
## than a 5th player's color.
const NEUTRAL_ART_FOLDERS := ["blue", "red", "green", "yellow"]
const NEUTRAL_TINT := Color(0.55, 0.55, 0.55)

## Returns the mesh resource path (color folder + level tier already
## resolved) for a base-attached or standalone building. `material` is only
## meaningful for `tower` (its stone/wood/steel variant); ignored otherwise.
static func mesh_path_for(building_type: String, level: int, material: String, owner_id: String) -> String:
	var name := _mesh_basename(building_type, level, material)
	if name.is_empty():
		return ""
	# A handful of entries are genuinely colorless (only exist in neutral/)
	# — those basenames are returned already-final by _mesh_basename via the
	# "neutral:" prefix convention below.
	if name.begins_with("neutral:"):
		return BUILDINGS_DIR + "neutral/" + name.trim_prefix("neutral:") + ".gltf"
	var folder := color_folder_for(owner_id)
	if folder == "neutral":
		folder = NEUTRAL_ART_FOLDERS[hash(building_type) % NEUTRAL_ART_FOLDERS.size()]
	return BUILDINGS_DIR + folder + "/" + name + "_" + folder + ".gltf"

## True when `mesh_path_for` had to borrow color-folder art for a
## neutral-owned building (see above) — the caller should apply NEUTRAL_TINT
## in that case. False for the genuinely-neutral "neutral:"-prefixed
## basenames (Farm/Harbour's plot mesh), which need no extra tint.
static func needs_neutral_tint(building_type: String, owner_id: String) -> bool:
	if owner_id != "neutral":
		return false
	return not _mesh_basename(building_type, 1, "").begins_with("neutral:")

static func _mesh_basename(building_type: String, level: int, material: String) -> String:
	match building_type:
		# --- Core / civic ---
		"hq":
			return "building_castle"
		"command_centre":
			return "building_townhall"
		# --- Troop production ---
		"barracks":
			return "building_barracks"
		"covert_works":
			return "building_tent"
		"factory", "tank_plant", "demolition_plant":
			return "building_workshop"
		"salvage_works":
			return "building_blacksmith"
		"covert_airfield", "iron_aviary", "hangar":
			# No aircraft-themed mesh in this medieval pack — thematic
			# stand-in, flagged in game-design/01-map-and-terrain.md.
			return "building_workshop"
		"blazeworks", "frostworks":
			return "building_workshop" # + ELEMENT_TINTS
		# --- Naval production ---
		"port":
			return "building_docks"
		"shipyard":
			return "building_shipyard"
		# --- Resource ---
		"farm":
			return "neutral:building_dirt"
		"harbour":
			return "neutral:building_dirt" # + fanned boat.gltf props, see building_view_3d.gd
		"mine", "quarry", "stone_works":
			return "building_mine"
		"lumber_mill", "forest_yard", "ford_yard":
			return "building_lumbermill"
		"oil_rig":
			return "building_well" # + dark tint stand-in, no oil-rig mesh available
		# --- Support ---
		"house":
			return "building_home_A" if level < 3 else "building_home_B"
		"healing_spire":
			return "building_church"
		"wind_sanctuary", "wind_spire":
			return "building_windmill"
		"radar_array":
			return "building_watchtower"
		"supply_depot":
			return "building_market"
		"ice_spire":
			return "building_shrine" # + blue tint
		# --- Defensive turret family (no dedicated mesh per sub-type —
		# shared 3-tier pool by level, tinted per element via ELEMENT_TINTS) ---
		"turret", "cold_turret", "emp_turret", "flame_turret", "grenade_turret", "sniper_turret", "water_turret", "wood_turret", "missile_launcher":
			if level <= 2:
				return "building_tower_base"
			elif level <= 4:
				return "building_tower_A"
			else:
				return "building_tower_cannon" if (level % 2 == 0) else "building_tower_catapult"
		# --- Standalone Tower (material-keyed) ---
		"tower":
			match material:
				"wood":
					return "building_watchtower"
				"steel":
					return "building_tower_cannon"
				_: # "stone" and unset
					return "building_tower_A" if level < 4 else "building_tower_B"
		"dock":
			return "building_docks"
		_:
			return "" # landmine, wall, road, bridge — not rendered here, see building_view_3d.gd

## Universal per-level growth cue, applied on top of whatever mesh got
## picked above — covers every building_type equally, including the many
## that only have one mesh variant and so get no tier-swap otherwise.
## Matches game-design/02-bases-and-buildings.md's stated intent ("a level
## shows up as ... a taller mine") in a way that generalizes past the two
## types (Farm/Harbour) that doc happens to spell out explicitly.
const LEVEL_SCALE_STEP := 0.06
const LEVEL_SCALE_MAX_STEPS := 6

## Flat multiplier under the per-level growth above — buildings read too big
## relative to squads/hex size at BASE_SCALE 1.0, so this shrinks every
## building uniformly (a level-7 Farm still ends up bigger than a level-1 one,
## just from a smaller starting point) rather than compressing the per-level
## growth curve itself.
const BASE_SCALE := 0.8

static func level_scale(level: int) -> float:
	return BASE_SCALE * (1.0 + clampi(level - 1, 0, LEVEL_SCALE_MAX_STEPS) * LEVEL_SCALE_STEP)

## Small thematic prop scattered around a building, one extra instance per
## level above 1 (capped) — "as buildings level up, add more decor": a
## cheap, uniform way to make growth read at a glance even for the many
## building_types stuck on a single mesh variant. Harbour is deliberately
## NOT listed here — its boats already have their own explicit per-level
## count spec (game-design/02-bases-and-buildings.md:235, count == level,
## not level-1) handled directly in building_view_3d.gd.
const LEVEL_DECOR_MAX := 5
const LEVEL_DECOR_BY_TYPE := {
	"hq": PROPS_DIR + "flag_%s.gltf", # color-specific — see level_decor_mesh_for
	"command_centre": PROPS_DIR + "flag_%s.gltf",
	"barracks": PROPS_DIR + "weaponrack.gltf",
	"covert_works": PROPS_DIR + "crate_A_small.gltf",
	"factory": PROPS_DIR + "crate_A_big.gltf",
	"tank_plant": PROPS_DIR + "crate_A_big.gltf",
	"demolition_plant": PROPS_DIR + "cannonball_pallet.gltf",
	"salvage_works": PROPS_DIR + "crate_open.gltf",
	"covert_airfield": PROPS_DIR + "crate_A_big.gltf",
	"iron_aviary": PROPS_DIR + "crate_A_big.gltf",
	"hangar": PROPS_DIR + "crate_A_big.gltf",
	"blazeworks": PROPS_DIR + "barrel.gltf",
	"frostworks": PROPS_DIR + "barrel.gltf",
	"port": PROPS_DIR + "anchor.gltf",
	"shipyard": PROPS_DIR + "anchor.gltf",
	"dock": PROPS_DIR + "boatrack.gltf",
	"mine": PROPS_DIR + "resource_stone.gltf",
	"quarry": PROPS_DIR + "resource_stone.gltf",
	"stone_works": PROPS_DIR + "resource_stone.gltf",
	"lumber_mill": PROPS_DIR + "crate_long_A.gltf",
	"forest_yard": PROPS_DIR + "crate_long_A.gltf",
	"ford_yard": PROPS_DIR + "crate_long_A.gltf",
	"oil_rig": PROPS_DIR + "bucket_water.gltf",
	"house": PROPS_DIR + "sack.gltf",
	"healing_spire": PROPS_DIR + "crate_open.gltf",
	"wind_sanctuary": PROPS_DIR + "sack.gltf",
	"wind_spire": PROPS_DIR + "cannonball_pallet.gltf",
	"radar_array": PROPS_DIR + "crate_open.gltf",
	"supply_depot": PROPS_DIR + "wheelbarrow.gltf",
	"ice_spire": PROPS_DIR + "cannonball_pallet.gltf",
	"turret": PROPS_DIR + "cannonball_pallet.gltf",
	"cold_turret": PROPS_DIR + "cannonball_pallet.gltf",
	"emp_turret": PROPS_DIR + "cannonball_pallet.gltf",
	"flame_turret": PROPS_DIR + "cannonball_pallet.gltf",
	"grenade_turret": PROPS_DIR + "cannonball_pallet.gltf",
	"sniper_turret": PROPS_DIR + "cannonball_pallet.gltf",
	"water_turret": PROPS_DIR + "cannonball_pallet.gltf",
	"wood_turret": PROPS_DIR + "cannonball_pallet.gltf",
	"missile_launcher": PROPS_DIR + "cannonball_pallet.gltf",
	"tower": PROPS_DIR + "cannonball_pallet.gltf",
}

static func level_decor_count(building_type: String, level: int) -> int:
	if not LEVEL_DECOR_BY_TYPE.has(building_type):
		return 0
	return clampi(level - 1, 0, LEVEL_DECOR_MAX)

## Resolves the %s color placeholder (flag_%s.gltf is the only per-color
## decor prop) for hq/command_centre; every other entry is already a
## complete, colorless path.
static func level_decor_mesh_for(building_type: String, owner_id: String) -> String:
	var path: String = LEVEL_DECOR_BY_TYPE.get(building_type, "")
	if path.find("%s") != -1:
		return path % color_folder_for(owner_id)
	return path

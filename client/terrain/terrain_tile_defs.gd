## Checked-in canonical connection masks for the directional river/road
## meshes in assets/tiles/{rivers,roads}/ — derived by tools/
## analyze_terrain_meshes.gd (headless vertex-color analysis, re-run by hand
## whenever the asset pack changes; see that file's header for the method).
##
## Each mask is 6 bits, bit i set iff this mesh (loaded unrotated, i.e.
## rotation_steps=0) connects toward HexCoord.DIRECTIONS[i] once placed at
## TerrainTileResolver's fixed calibration rotation — see that file's header
## for the full derivation of why local mesh geometry maps to HexCoord
## direction indices this way. Binary literals below are written bit5..bit0
## left-to-right (e.g. 0b001001 has bit3 and bit0 set), matching the
## analyzer's own printed output exactly, so a value here can be diffed
## against a fresh analyzer run by eye.
##
## `hex_river_A_curvy` intentionally shares A's mask (a visual-variety
## alternate for the same connectivity, not a distinct shape). `hex_river_I`,
## `hex_river_crossing_A`, and `hex_river_crossing_B` are all rotations of
## each other under the mask alone — a hex only has 3 possible "straight
## line through the center" directions, so any 2-of-3 combination (which is
## what "two straight rivers crossing" is) is necessarily a rotation of
## either other combination. Real, expected, not an analyzer bug (see
## tools/analyze_terrain_meshes.gd's collision self-check output). The
## resolver treats same-mask entries as interchangeable alternates.
class_name TerrainTileDefs
extends RefCounted

const RIVER_MASKS := {
	"hex_river_A": 0b001001,
	"hex_river_A_curvy": 0b001001,
	"hex_river_B": 0b001010,
	"hex_river_C": 0b001100,
	"hex_river_D": 0b101010,
	"hex_river_E": 0b001011,
	"hex_river_F": 0b101001,
	"hex_river_G": 0b011100,
	"hex_river_H": 0b011101,
	"hex_river_I": 0b110110,
	"hex_river_J": 0b111001,
	"hex_river_K": 0b111110,
	"hex_river_L": 0b111111,
	"hex_river_crossing_A": 0b101101,
	"hex_river_crossing_B": 0b011011,
}

const ROAD_MASKS := {
	"hex_road_A": 0b001001,
	"hex_road_B": 0b001010,
	"hex_road_C": 0b001100,
	"hex_road_D": 0b101010,
	"hex_road_E": 0b001011,
	"hex_road_F": 0b101001,
	"hex_road_G": 0b011100,
	"hex_road_H": 0b011101,
	"hex_road_I": 0b110110,
	"hex_road_J": 0b111001,
	"hex_road_K": 0b111110,
	"hex_road_L": 0b111111,
	"hex_road_M": 0b001000,
}

## Neither set has a dedicated 0-connection (isolated hex) mesh, and the
## river set specifically has no 1-connection "source/end" mesh either (a
## generated river's actual source hex always has exactly 1 connection) —
## TerrainTileResolver.resolve()'s best-effort superset fallback handles
## both cases generically, no explicit fallback entry needed here.

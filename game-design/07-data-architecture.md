# Data Architecture

This document lays out how the game's core concepts map to actual stored data —
definitions (static, authored once) vs. instances (live, per-match state).

## 1. Materials (Wood/Stone/Steel) for Multi-Material Buildings
Buildings that come in multiple materials (Tower, Wall, Dock, Bridge) are **one
building type each**, not separate types per material. Stat/growth/cost tables are
keyed by material:
```
BuildingDef["Tower"]["stone"] = { base_stats, stat_growth, base_cost, cost_growth }
BuildingDef["Tower"]["wood"]  = { base_stats, stat_growth, base_cost, cost_growth,
                                   adds_turret_per_level: true }
BuildingDef["Wall"]["wood"]   = { base_stats, stat_growth, base_cost, cost_growth,
                                   damage_received_modifiers: { Fire: 2.0 } }
BuildingDef["Wall"]["stone"]  = { ... }
BuildingDef["Wall"]["steel"]  = { ... }
```
A built instance stores which type + which material it was built as; material is
fixed at construction time. (Whether a destroyed-and-rebuilt ruin can switch material
is an open decision — see Open Items.)

## 2. Walls
Walls sit on hex **borders**, not on a hex itself, so they're keyed by an edge, not a
tile:
```
Wall {
  id,
  edgeKey: "hexA|hexB"   // canonical sorted pair of adjacent hex coordinates
  ownerId,
  material,              // wood / stone / steel
  level,
  currentHP
}
```
Stored in its own table, separate from tile-based `BuildingInstance` records.

## 3. Building Instances (including Health)
Every non-HQ building (and HQ, structurally, though it's indestructible) tracks its
own live health independently of its static definition:
```
BuildingInstance {
  id,
  baseId,               // which base this belongs to (null for standalone Dock/Road/Bridge/Tower)
  buildingType,
  material,             // only relevant for Tower/Wall/Dock/Bridge
  hex,
  level,
  currentHP,            // depletes under attack; building def determines maxHP at current level
  ruinState: null | { destroyedAt, rebuildCost }   // set when currentHP hits 0
}
```
- **currentHP is always tracked per instance**, separate from the definition's
  `maxHP-at-this-level` — this is what actually depletes during a siege.
- When `currentHP` reaches 0, the instance flips into `ruinState` (per
  `06-building-stats-and-defenses.md`'s ruin rules) rather than being deleted — the
  hex/edge stays occupied, and the owner can pay `rebuildCost` (a fraction of original
  cost) to restore it to the same building type/material at level 1.

## 4. Troop Runtime State
Static troop definitions (from `05-troop-stat-schema.md`) are separate from live
per-unit instances:
```
TroopInstance {
  id,
  unitType,
  ownerId,
  squadId,              // nullable
  commanderId,           // nullable, set if part of a Commander-led mixed squad
  position: {x, y},      // continuous open-field position, not tile-locked
  currentHex,            // cached/recomputed on move, for terrain & vision lookups
  currentHP,
  activeBuffs: [
    { source, effect, magnitude, expiresAt }   // auras, deficit-drain, etc.
  ],
  fuelStatus             // only relevant for aircraft/vehicles
}
```
Buffs/debuffs (Shield Tank auras, Food/Fuel deficit drain, terrain bonuses) are
computed each tick from what's currently in range/in effect, not baked permanently
into the unit's stats.

## 5. Base & Ownership
Buildings don't carry their own `ownerId` — ownership is derived from the **Base**
they belong to, and the Base belongs to a Player:
```
Base {
  id,
  baseType,             // Capital / Fort Irongrad / Firebase / Air Temple / Treehouse / Kraken Point / etc.
  ownerId,              // nullable if neutral/unclaimed
  hqLevel,
  hexCoord,             // the base's map location
  buildings: [BuildingInstance...]
}

Player {
  id,
  ownedBaseIds: [...],
  resources: { food, steel, fuel, stone, wood }
}
```
- When a base is captured, only `Base.ownerId` changes — every `BuildingInstance`
  underneath it (including its current HP/ruin state) carries over unchanged. This
  matches the earlier rule that capturing a base means inheriting everything already
  built there.

## 6. Map & Terrain Storage
```
Tile {
  hexCoord,
  terrainType,          // Plains / Forest / Hill / River / Coast / Ocean
  biomePatchId           // which forest/hill cluster this tile belongs to, if any
}
```
- **Rivers**: generated as a connected path of River-tagged tiles running from an
  interior source point to a coastline tile — e.g. via a constrained random walk or
  flow-simulation toward the nearest coast edge, marking tiles as River along the way.
  Generation is validated against the balance constraints already established (a river
  can't fully wall off a Capital's expansion paths).
- **Forest/Hill biomes**: generated via seed points + blob/flood-fill growth to a
  randomized patch size (small/medium/large), then stamped onto the tile grid —
  standard procedural terrain-clustering approach.

## 7. Resources — Storage & Tick
- Resources are a **shared pool per player**, not per-base — each base's production
  buildings feed into one pool on the `Player` record (see Base & Ownership above).
- **Tick interval: every 5 seconds.** At each tick:
  1. Sum production from all owned bases' resource buildings (Farm/Quarry/Mine/Oil
     Rig/Lumber Mill, at their current level).
  2. Subtract upkeep (Food for all troops/bases; Fuel for moving vehicles and
     un-docked aircraft, per the fuel rules in `03-resources.md`).
  3. Apply the net delta to the player's resource pool.
  4. If a resource is in deficit, apply the active-drain effect to affected
     troops/vehicles (per `03-resources.md`).
- This is fully automatic — no player action triggers a tick. Any real-time "counting
  up" shown in the UI between ticks is a visual interpolation only; the tick is the
  actual source of truth.
- A 5-second tick over a 40-minute match is 480 ticks total — frequent enough to feel
  responsive, coarse enough to keep the simulation/sync simple.

## Open / Unresolved Items
- Whether rebuilding a ruined multi-material building (Tower/Wall/Dock/Bridge) allows
  choosing a new material, or must match what was destroyed.
- Whether `TroopInstance.position` needs a separate "facing" for visual/animation
  purposes, or if that's purely a rendering concern outside this schema.
- Exact list of what counts toward `activeBuffs` vs. what's computed live from terrain
  each frame without being stored as a discrete buff entry (e.g. is "standing on a
  hill" a stored buff, or just checked live off `currentHex`?).

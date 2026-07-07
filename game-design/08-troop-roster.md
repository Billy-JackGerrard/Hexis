# Troop Roster (In Progress)

This document tracks confirmed troop types and flags what's still undecided. Full
stats (HP, damage, speed, splash radius, fuel use) are locked in for every troop
except the Commander roster — see `data/troops/*.json` for authoritative values; this
doc records design rationale, not the numbers themselves.

## General Design Intent
- A long roster with real differentiation: some units are fast/fragile, some are
  strong against specific troop types but weak against others, some specialize
  against buildings/walls.
- Wall material matters tactically: Wood walls (cheapest/weakest) are specifically
  vulnerable to flame-based troops.
- Infantry's counter-role vs. heavy armor: rather than only expressing "bad vs.
  Infantry" as a damage-modifier penalty, some heavy tanks (Rocket Tank, Granite
  Crumbler) omit `Infantry` from `canTarget` entirely — they physically cannot
  engage Infantry at all. This gives massed Infantry a genuine niche (soaking up
  heavy armor that can't shoot back) rather than just taking reduced damage from it.

## Confirmed Units by Building

### Capital Base
| Building | Unit(s) | Notes |
|---|---|---|
| Barracks | **Rifleman** | Basic, cheap infantry — the default Food-upkeep swarm unit |
| Barracks | **Grenadier** | Anti-tank infantry, bonus damage vs. `Land`-domain targets (land vehicles specifically — does not apply to Air/Naval vehicles) |
| Barracks | **Flamethrower** | Bonus damage vs. `Wood`-tagged targets (walls, docks, bridges, Wood Tower) |
| Barracks | **Sniper** | Stealth unit; also a `detector` (spots other stealthed units at full vision range); `damage_types: [Piercing]` — bypasses target armor (not damage-received modifiers, which still apply normally); `can_target` omits `Structure` (**cannot target buildings/walls**), a deliberate exception to the usual default (see `05-troop-stat-schema.md`) |
| Barracks | **Shielder** | Pure tank/meatshield: `can_target: []` (no attack at all), high HP plus a flat `armor` stat (damage reduction per hit, distinct from the multiplier-based damage-received modifiers), slow-moving |
| Factory | **Ambulance** | Light support vehicle — mobile heal aura, Infantry-only (same effect family as Hospital's passive heal); a vehicle rather than infantry so it can keep pace with the army it's healing. Repair Truck (Camp Cosy's Supply Depot) is its Land-vehicle counterpart |
| Factory | **Transport Truck** | Light vehicle, little/no attack — carries an infantry squad aboard for fast repositioning, letting cheap Food-upkeep infantry keep up with Fuel-upkeep armies. Can deploy its cargo **mid-battle**, not just while idle. `cargoCapacity: 1` = one squad (any size), not troop headcount |
| Factory | **Light Tank** | Generic all-round light vehicle — no damage modifiers vs. anything; the baseline other tank types (Heavy Tank roster, etc.) get balanced against, same role Rifleman plays for infantry |
| Factory | **Tonk** | Heavier/longer-range sibling to Light Tank — slower attack speed, higher per-hit damage, longer range; slight damage bonus vs. Air and vs. Structure (buildings+walls) |
| Factory | **Basekiller** | Dedicated siege unit — large (2.5x) bonus vs. `Defensive`-category buildings specifically (base defenses), cannot target Infantry |
| Factory | (Engineer, Tonk, Ambulance, Light Tank, Transport Truck, Basekiller — full roster, see rows above) | Only *light* vehicles — heavy tanks require Fort Irongrad/Winter Forge |
| Port | **Gunboat** | Generic all-round early-tier warship, no damage modifiers vs. anything. Requires water-adjacent tile |
| Port | **HMS Cuddles** | Lightly armed troop transport (weak attack, unlike Transport Truck), `cargoCapacity: 1` (one Infantry squad). Unlike Transport Truck/Aircraft Carrier, **cannot** launch cargo mid-combat — must be idle/docked to unload. Requires water-adjacent tile |
| Factory | **Engineer** | `Domain: Land · Tags: [Vehicle, Support]`. Level-1 Factory unlock (available the moment a base has a Factory at all). Builds Roads, Bridges, Docks, Towers anywhere, including behind enemy lines, once produced — non-combat (`can_target: []`) |
| Command Centre | **Commander** | `max_squad_size: 1` (never merges), `max_squads_led: 4`. Only unit that allows combined-arms play. Capital-only. Fairly expensive; has its own combat stats plus a unique buff aura per Commander (small named roster, not one generic unit). Squads assigned to it form a **regiment** (up to 4 squads) that follows it (see `04-combat.md`). Full roster/abilities TBD |

### Fort Irongrad
| Building | Unit(s) | Notes |
|---|---|---|
| Tank Plant | **Juggernaut** | Baseline heavy generalist, no damage modifiers — the Heavy Tank roster's Rifleman/Light Tank equivalent. Also built at Winter Forge's Frostworks. Stats implemented, see `data/troops/juggernaut.json` |
| Tank Plant | **Rocket Tank** | Dedicated AA heavy tank — fills the roster's long-open anti-air gap. **Cannot target Infantry at all** (omitted from `canTarget`, not just a penalty — see Infantry-counters-armor note below). `damageDealtModifiers: {Air: 2.0, Naval: 1.6, Structure: 0.7}`, slight armor (3), 20% chance to `stun` on hit. Also built at Winter Forge's Frostworks. Stats implemented, see `data/troops/rocket_tank.json` |
| Tank Plant | **Granite Crumbler** | Long-range indirect siege tank — highest range/per-hit damage in the roster, splash. **Cannot target Infantry at all** (omitted from `canTarget`). `damageDealtModifiers: {Structure: 2.0, Defensive: 1.6}`. Irongrad-exclusive (not built at Frostworks). Stats implemented, see `data/troops/granite_crumbler.json` |
| Tank Plant | **Chonky** | Armored brawler — highest HP in the roster plus flat armor (8), very short range, bonus vs. Infantry (1.5x, crush). Irongrad-exclusive (not built at Frostworks). Stats implemented, see `data/troops/chonky.json` |

### Winter Forge
| Building | Unit(s) | Notes |
|---|---|---|
| Frostworks | **Frost Tank** | Ice-themed control unit — 25% chance to `freeze` on hit, ties into Winter Forge's Cold Turret/Ice Spire identity. Frostworks-exclusive (not built at Tank Plant). Frostworks' level-1 unlock. Stats implemented, see `data/troops/frost_tank.json` |
| Frostworks | Juggernaut, Rocket Tank (shared w/ Tank Plant) | Frostworks' level-2/3 unlocks, in that order. See Fort Irongrad above |

### Firebase
| Building | Unit(s) | Notes |
|---|---|---|
| Blazeworks | **Flamecopter** (renamed from Flame Helicopter) | Short range, high splash, fire damage. Cannot target Air. Stats implemented, see `data/troops/flamecopter.json` |
| Blazeworks | **Plasmacopter** (renamed from Plasma Helicopter) | Bigger, slower, longer range, explosive impact damage. Stats implemented, see `data/troops/plasmacopter.json` |

### Windy Peaks (renamed from Air Temple)
| Building | Unit(s) | Notes |
|---|---|---|
| Wind Sanctuary | Glider | Wind Sanctuary's level-1 unlock. Excellent scout — fast, high vision range. **Cannot attack at all** (`can_target: []`). Cheap. Uses **no Fuel** — unpowered, so it draws Food upkeep instead, like infantry. Stats implemented, see `data/troops/glider.json` |
| Wind Sanctuary | Hot Air Balloon | Wind Sanctuary's level-2 unlock. Cheap, high splash, low range, ground/naval targets only (includes Infantry), slow. Modest Fuel upkeep. Stats implemented, see `data/troops/hot_air_balloon.json` |

### Treehouse
| Building | Unit(s) | Notes |
|---|---|---|
| Barracks | Rifleman, Grenadier, Flamethrower, Shielder, Sniper (shared w/ Capital roster) | |
| Forest Yard | **Quad-bike** | Fast, ignores forest vehicle-block, low armor/damage. Stats implemented, see `data/troops/quad_bike.json` |

### Kraken Point
| Building | Unit(s) | Notes |
|---|---|---|
| Port | Gunboat, HMS Cuddles | Kraken Point separately builds Port too (any water-adjacent base can) — not part of Shipyard's own unlock list. See Capital Base above |
| Shipyard | **Destroyer** | Heavier warship — deliberately not just a stronger Gunboat: slower and pricier, but tankier and specializes with bonuses vs. `Land` (1.4x) and `Structure` (1.2x), a bombardment/shore-support role rather than a straight upgrade or an anti-ship specialist (that's Submarine's job). Gunboat remains the fast/cheap early pick. Kraken Point exclusive (not built at Ford Yard). Stats implemented, see `data/troops/destroyer.json` |
| Shipyard | **Submarine** | Stealth ambush ship — the naval sibling to Ghost Tank. `canTarget: [Naval]` only (pure ship-hunter). `stealth`/`revealRange`/`revealsOnAttack` same mechanism as Ghost Tank. Also built at Rivergate's Ford Yard. Stats implemented, see `data/troops/submarine.json` |
| Shipyard | **Tank Carrier** (renamed from the roster's planned "Heavy Transport") | Bigger than HMS Cuddles, fully unarmed, `cargoCapacity: 2`, `cargoAllowedTags: [Land, Infantry]` — the first transport that can carry vehicle squads, not just Infantry. `canLaunchCargoMidCombat: true`. Kraken Point exclusive (not built at Ford Yard). Stats implemented, see `data/troops/tank_carrier.json` |
| Shipyard | **Aircraft Carrier** | Naval capstone — highest HP/cost/slowest ship in the navy. Holds (doesn't produce) 2 Air squads fuel-free, and can **launch them mid-battle**. Its own weak armament is `canTarget: [Air]` only (point-defense flak) — cannot fire on ships/ground/structures, so always needs an escort fleet against anything but an air threat. Kraken Point exclusive. Stats implemented, see `data/troops/aircraft_carrier.json` |

### Sky Fortress
| Building | Unit(s) | Notes |
|---|---|---|
| Iron Aviary | **Wingfighter** | Fast, rapid-fire machine guns. Low damage against buildings/walls — anti-troop dogfighter, not a siege unit. Stats implemented, see `data/troops/wingfighter.json` |
| Iron Aviary | **Thunder** (renamed from Falcon) | Slower, heavier armored, missile-armed — hits harder per shot, small splash, less mobile than Wingfighter. Stats implemented, see `data/troops/thunder.json` |
| Iron Aviary | **Cargocopter** | Level-3 unlock. Fully unarmed (`canTarget: []`), `cargoCapacity: 2`, `cargoAllowedTags: [Infantry]`, `canLaunchCargoMidCombat: true` — the Air-domain troop carrier, rounding out Transport Truck (Land)/HMS Cuddles & Tank Carrier (Naval) with an Infantry-only helicopter airlift. **`cargoRequiresBuildingDock: true`** — unlike every other transport, it can only board/unload Infantry while sitting on a Hangar hex (see `04-combat.md`'s Cargo section and `05-troop-stat-schema.md`'s Transport/Cargo section) — a helicopter needs a landing pad, and Air has no terrain-driven pickup restriction the way Naval carriers get from the coastline rule. Stats implemented, see `data/troops/cargocopter.json`; Hangar is buildable at Sky Fortress (`data/bases/sky_fortress.json`) |

### Foundry Reach
| Building | Unit(s) | Notes |
|---|---|---|
| Factory | Shared w/ Capital roster (Engineer, Tonk, Ambulance, Light Tank, Transport Truck, Basekiller) | No unique units — Foundry Reach's identity is its Mine/Stone Works economy, not its troops |

### Signal Ridge
| Building | Unit(s) | Notes |
|---|---|---|
| Covert Works | **Ghost Tank** | Domain: Land · Tags: `[Vehicle, Tank, Stealth]`. `stealth: true`, `reveal_range`: very short (visible to any non-detector unit/building at close range). `detector` units (e.g. Sniper) see it at their normal vision range instead. `reveals_on_attack: true` — firing makes it visible to everyone until a few seconds pass without attacking, then it re-cloaks. Stats implemented, see `data/troops/ghost_tank.json` |
| Covert Works | **Disruptor** | Domain: Land · Tags: `[Vehicle, Support]`. `can_target: []` (non-combat, like Engineer). Aura: `{radius: 6, target: enemy_buildings, filter: "Defensive", effect: suppress_targeting}` — must be escorted into enemy base range to matter; killing it restores suppressed defenses immediately. Stats implemented, see `data/troops/disruptor.json` |

### Rivergate
| Building | Unit(s) | Notes |
|---|---|---|
| Ford Yard | **Amphibious Raider** | Domain: Land · Tags: `[Vehicle, Light, Amphibious]` — a **vehicle**, not infantry. Terrain override: `ignores_river_block: true` (fords rivers without a Bridge). Low armor, fast, Fuel upkeep like any land vehicle. Stats implemented, see `data/troops/amphibious_raider.json` |
| Ford Yard | Submarine (shared w/ Kraken Point Shipyard) | Ford Yard's second unlock, alongside Amphibious Raider — not Destroyer/Tank Carrier/Aircraft Carrier, which stay Shipyard-exclusive. See Kraken Point above |

### Camp Cosy
| Building | Unit(s) | Notes |
|---|---|---|
| Supply Depot | **Engineer**, **Ambulance**, **Transport Truck**, **Repair Truck**, **Mule**, **Volt Truck** | All non-combat (`can_target: []`) — a support-vehicle-only roster, distinct from Factory's combat vehicles. Engineer/Ambulance/Transport Truck are shared with Factory (see Capital Base above). Repair Truck heals Land vehicles (Ambulance's counterpart, which now heals Infantry only); Mule reduces nearby troops' Food/Fuel upkeep; Volt Truck boosts speed + attack speed for Land/Air/Naval. Stats implemented, see `data/troops/repair_truck.json`, `data/troops/mule.json`, `data/troops/volt_truck.json` |

**Resolved: healing has a deliberate rarity progression by Domain, and Air currently
has no healing option at all.** Infantry healing (Hospital's passive aura, Ambulance's
mobile aura) is available to every base via Factory/Capital. Land-vehicle healing
(Repair Truck) is gated behind Camp Cosy's Supply Depot — one specific Unique base,
not universally available. Air has no repair/heal unit or building at all — this is
an intentional gap for now, not an oversight, consistent with healing getting rarer
by Domain (Infantry → common, Land vehicles → one Unique base, Air → none yet). If a
future pass adds aircraft healing, it should sit at least as rare as Repair Truck to
preserve that progression.
| Barracks | Rifleman, Grenadier, Flamethrower, Shielder, Sniper (shared w/ Capital roster) | Camp Cosy's only source of combat troops — Supply Depot's roster can't defend the base at all |

## Fuel/Maintenance Quick Reference
- Land vehicles: free while stationary, consume Fuel while moving.
- Aircraft: heavy Fuel consumption, **always paid while airborne** — no near-base
  fuel-free rule. Fuel-free only while actually docked: aboard an Aircraft Carrier, or
  landed inside a Hangar (a dedicated storage building, distinct from Iron Aviary/
  Blazeworks — see `03-resources.md`). Docked aircraft are also hidden from enemy
  vision/detection/targeting.
- Ships: consume very little Fuel regardless of state.
- **Exception — Glider** (Windy Peaks): unpowered, so it uses **no Fuel at all** and
  draws Food upkeep instead, same as ground infantry.

## Still To Do
- [x] Named infantry roster (Barracks): Rifleman, Grenadier, Flamethrower, Shielder, Sniper — full stats implemented, see `data/troops/`
- [x] Anti-air vehicle/tank — **Rocket Tank** (Fort Irongrad Tank Plant / Winter Forge Frostworks), see `data/troops/rocket_tank.json`
- [x] Full light/combat vehicle roster (Factory): Engineer, Tonk, Ambulance, Light Tank, Transport Truck, Basekiller — see `data/troops/`. Camp Cosy's Supply Depot additionally fields a dedicated support-vehicle roster (Repair Truck, Mule, Volt Truck alongside shared Engineer/Ambulance/Transport Truck)
- [x] Basic navy roster (Port): Gunboat, HMS Cuddles — see `data/troops/`
- [x] Wingfighter/Thunder (Sky Fortress) full stat sheet — see `data/troops/wingfighter.json`, `data/troops/thunder.json`
- [x] Full Kraken Point Shipyard roster (ship tiers up to Aircraft Carrier) — Destroyer, Submarine, Tank Carrier, Aircraft Carrier; see `data/troops/destroyer.json`, `data/troops/submarine.json`, `data/troops/tank_carrier.json`, `data/troops/aircraft_carrier.json`. Cruiser/Battleship tier deliberately deferred
- [x] Engineer combat stats — non-combat (`canTarget: []`), Land-domain vehicle, hp 60, cheap/fast to produce, level-1 Factory unlock; see `data/troops/engineer.json`
- [x] Named Commander roster + each Commander's unique buff/ability — full basic/rare/best set implemented: **Vanguard** (basic), a Land-vehicle Commander whose aura gives its regiment's squads a 1.8x speed boost; **Nightfall** (rare), a stealthy Land-vehicle Commander whose aura extends its own Ghost-Tank-style stealth (revealRange 1, revealsOnAttack) to every squad in its regiment; and **Warden** (best), a tanky support Commander whose aura heals itself and its regiment once out of combat (`heal_out_of_combat`, gated like buildings' passive regen, unlike Ambulance/Repair Truck's always-on heal). All three scope their aura via `filter: "own_regiment"` (Warden: `"own_regiment_and_self"`) rather than proximity, capped at `maxSquadsLed: 4`. See `data/troops/commander_vanguard.json`, `data/troops/commander_nightfall.json`, `data/troops/commander_warden.json`
- [x] Full stat sheet: HP, damage, speed, cost, splash radius, range for every unit — done for every non-Commander troop, see `data/troops/`
- [ ] Rock-paper-scissors matchup matrix — per-unit damage modifiers are authored, but no consolidated summary matrix exists yet
- [x] Heavy Tank roster + which types are Irongrad-only vs. shared with Winter Forge's
      Frostworks — Juggernaut, Rocket Tank shared; Granite Crumbler, Chonky Irongrad-only;
      Frost Tank Frostworks-only. See `data/troops/juggernaut.json`,
      `data/troops/rocket_tank.json`, `data/troops/granite_crumbler.json`,
      `data/troops/chonky.json`, `data/troops/frost_tank.json`
- [x] Dedicated siege unit(s) — **Basekiller** (Factory), see `data/troops/basekiller.json`. Also introduced the `Defensive` reserved value (split out from `Structure`) for base-defenses-specific targeting/bonuses, and the "damage-modifier bonus = target-priority hint" rule (see `05-troop-stat-schema.md`/`04-combat.md`)
- [x] Quad-bike (Treehouse) full stat sheet — see `data/troops/quad_bike.json`

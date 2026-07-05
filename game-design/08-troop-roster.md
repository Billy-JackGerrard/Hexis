# Troop Roster (In Progress)

This document tracks confirmed troop types and flags what's still undecided. Full
stats (HP, damage, speed, splash radius, fuel use, rock-paper-scissors matchups) have
not been locked in yet — this is a placeholder structure to fill in next.

## General Design Intent
- A long roster with real differentiation: some units are fast/fragile, some are
  strong against specific troop types but weak against others, some specialize
  against buildings/walls.
- Wall material matters tactically: Wood walls (cheapest/weakest) are specifically
  vulnerable to flame-based troops.

## Confirmed Units by Building

### Capital Base
| Building | Unit(s) | Notes |
|---|---|---|
| Barracks | **Rifleman** | Basic, cheap infantry — the default Food-upkeep swarm unit |
| Barracks | **Grenadier** | Anti-tank infantry, bonus damage vs. `Land`-domain targets (land vehicles specifically — does not apply to Air/Naval vehicles) |
| Barracks | **Flamethrower** | Bonus damage vs. `Wood`-tagged targets (walls, docks, bridges, Wood Tower) |
| Barracks | **Sniper** | Stealth unit; also a `detector` (spots other stealthed units at full vision range); `damage_types: [Piercing]` — bypasses target damage-received modifiers; `can_target` omits `Structure` (**cannot target buildings/walls**), a deliberate exception to the usual default (see `05-troop-stat-schema.md`) |
| Barracks | **Shielder** | Pure tank/meatshield: `can_target: []` (no attack at all), high HP plus a flat `armor` stat (damage reduction per hit, distinct from the multiplier-based damage-received modifiers), slow-moving |
| Factory | **Ambulance** | Light support vehicle — mobile heal aura (same effect family as Hospital's passive heal); a vehicle rather than infantry so it can keep pace with the army it's healing |
| Factory | **Transport Carrier** | Light vehicle, little/no attack — carries an infantry squad aboard for fast repositioning, letting cheap Food-upkeep infantry keep up with Fuel-upkeep armies. Can deploy its cargo **mid-battle**, not just while idle. `cargoCapacity: 1` = one squad (any size), not troop headcount |
| Factory | **Light Tank** | Generic all-round light vehicle — no damage modifiers vs. anything; the baseline other tank types (Heavy Tank roster, etc.) get balanced against, same role Rifleman plays for infantry |
| Factory | **Tonk** | Heavier/longer-range sibling to Light Tank — slower attack speed, higher per-hit damage, longer range; slight damage bonus vs. Air and vs. Structure (buildings+walls) |
| Factory | **Basekiller** | Dedicated siege unit — `prioritizeStructures: true`, large (2.5x) bonus vs. `Defensive`-category buildings specifically (base defenses), cannot target Infantry |
| Factory | Further light vehicles (roster TBD) | Only *light* vehicles — heavy tanks require Fort Irongrad |
| Port | **Gunboat** | Generic all-round early-tier warship, no damage modifiers vs. anything. Requires water-adjacent tile |
| Port | **Landing Craft** | Fully unarmed troop transport, `cargoCapacity: 1` (one Infantry squad). Unlike Transport Carrier/Aircraft Carrier, **cannot** launch cargo mid-combat — must be idle/docked to unload. Requires water-adjacent tile |
| — | **Engineer** | Builds Roads, Bridges, Docks, Towers. Buildable anywhere including behind enemy lines. Combat stats TBD (likely weak/no combat) |
| Command Centre | **Commander** | `max_squad_size: 1` (never merges), `max_squads_led: 4`. Only unit that allows combined-arms play. Capital-only. Fairly expensive; has its own combat stats plus a unique buff aura per Commander (small named roster, not one generic unit). Squads assigned to it form a **regiment** (up to 4 squads) that follows it (see `04-combat.md`). Full roster/abilities TBD |

### Fort Irongrad
| Building | Unit(s) | Notes |
|---|---|---|
| Tank Plant | Heavy Tank (full roster) | Builds in batches of 3-5. Most complete source of heavy tanks — Winter Forge's Hot Forge (below) also builds a subset of the same roster, so this is no longer an exclusive monopoly |

### Winter Forge
| Building | Unit(s) | Notes |
|---|---|---|
| Hot Forge | Heavy Tank (partial roster — subset of Tank Plant's list) | First case of a troop type split across more than one production building; exact which tank types land here vs. Irongrad-only is still TBD |

### Firebase
| Building | Unit(s) | Notes |
|---|---|---|
| Fire Helipad | Flame Helicopter | Short range, high splash, fire damage |
| Fire Helipad | Plasma Helicopter | Bigger, slower, longer range, explosive impact damage |

### Windy Peaks (renamed from Air Temple)
| Building | Unit(s) | Notes |
|---|---|---|
| Wind Sanctuary | Hot Air Balloon | Cheap, high splash, low range, ground/naval targets only, slow. Modest Fuel upkeep |
| Wind Sanctuary | Glider | Excellent scout — fast, high vision range. **Cannot attack at all** (`can_target: []`). Cheap. Uses **no Fuel** — unpowered, so it draws Food upkeep instead, like infantry |

### Treehouse
| Building | Unit(s) | Notes |
|---|---|---|
| Barracks | Rifleman, Grenadier, Flamethrower, Sniper (shared w/ Capital roster) | |
| Quad Hangar | Quad-bike | Fast, ignores forest vehicle-block, low armor/damage |

### Kraken Point
| Building | Unit(s) | Notes |
|---|---|---|
| Shipyard | Full navy roster incl. Aircraft Carrier | Aircraft Carrier can *hold* (not produce) most air troops fuel-free, and can **launch them mid-battle** (not just while idle/docked) |

### Sky Fortress
| Building | Unit(s) | Notes |
|---|---|---|
| Hangar | Wingfighter | Fast, rapid-fire machine guns. Low damage against buildings/walls — anti-troop dogfighter, not a siege unit |
| Hangar | Falcon | Slower, heavier armored, missile-armed — hits harder per shot, less mobile than Wingfighter |

### Foundry Reach
| Building | Unit(s) | Notes |
|---|---|---|
| Factory | Shared w/ Capital roster (Ambulance, Transport Carrier, further light vehicles TBD) | No unique units — Foundry Reach's identity is its Smeltery, not its troops |

### Signal Ridge
| Building | Unit(s) | Notes |
|---|---|---|
| Covert Works | **Ghost Tank** | Domain: Land · Tags: `[Vehicle, Tank, Stealth]`. `stealth: true`, `reveal_range`: very short (visible to any non-detector unit/building at close range). `detector` units (e.g. Sniper) see it at their normal vision range instead. `reveals_on_attack: true` — firing makes it visible to everyone until a few seconds pass without attacking, then it re-cloaks |
| Covert Works | **Disruptor** | Domain: Land · Tags: `[Vehicle, Support]`. `can_target: []` (non-combat, like Engineer). Aura: `{radius: X, target: enemy_buildings, filter: "Defensive", effect: suppress_targeting}` — must be escorted into enemy base range to matter; killing it restores suppressed defenses immediately |

### Rivergate
| Building | Unit(s) | Notes |
|---|---|---|
| Ford Yard | **Amphibious Raider** | Domain: Land · Tags: `[Vehicle, Light, Amphibious]` — a **vehicle**, not infantry. Terrain override: `ignores_river_block: true` (fords rivers without a Bridge). Low armor, fast, Fuel upkeep like any land vehicle |

## Fuel/Maintenance Quick Reference
- Land vehicles: free while stationary, consume Fuel while moving.
- Aircraft: heavy Fuel consumption, free while stationed adjacent to a base.
- Ships: consume very little Fuel regardless of state.
- **Exception — Glider** (Windy Peaks): unpowered, so it uses **no Fuel at all** and
  draws Food upkeep instead, same as ground infantry.

## Still To Do
- [x] Named infantry roster (Barracks): Rifleman, Grenadier, Flamethrower, Sniper — full stats implemented, see `data/troops/`
- [ ] Anti-air vehicle/tank (replaces an earlier AA-infantry idea — AA is now planned as a tank role, likely Factory or Fort Irongrad, not Barracks)
- [ ] Full light vehicle roster (Factory), beyond Ambulance/Transport Carrier
- [ ] Full basic navy roster (Port)
- [ ] Wingfighter/Falcon (Sky Fortress) full stat sheet
- [ ] Full Kraken Point Shipyard roster (ship tiers up to Aircraft Carrier)
- [x] Engineer combat stats — non-combat (`canTarget: []`), hp 40, cheap/fast to produce; see `data/troops/engineer.json`
- [ ] Named Commander roster + each Commander's unique buff/ability
- [ ] Full stat sheet: HP, damage, speed, cost, splash radius, range for every unit
- [ ] Rock-paper-scissors matchup matrix
- [ ] Which specific Heavy Tank types are Irongrad-only vs. shared with Winter Forge's
      Hot Forge
- [x] Dedicated siege unit(s) — **Basekiller** (Factory), see `data/troops/basekiller.json`. Also introduced the `Defensive` reserved value (split out from `Structure`) for base-defenses-specific targeting/bonuses, and the "damage-modifier bonus = target-priority hint" rule (see `05-troop-stat-schema.md`/`04-combat.md`)

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
| Barracks | Infantry (roster TBD) | |
| Factory | Light land vehicles (roster TBD) | Only *light* vehicles — heavy tanks require Fort Irongrad |
| Port | Basic navy (roster TBD, small) | Requires water-adjacent tile |
| — | **Engineer** | Builds Roads, Bridges, Docks. Buildable anywhere including behind enemy lines. Combat stats TBD (likely weak/no combat) |
| — | **Commander** | Only unit that allows mixed-type squads. Capital-only. Stats TBD |

### Fort Irongrad
| Building | Unit(s) | Notes |
|---|---|---|
| Tank Plant | Heavy Tank | Builds in batches of 3-5. Only source of heavy tanks in the game |

### Firebase
| Building | Unit(s) | Notes |
|---|---|---|
| Fire Helipad | Flame Helicopter | Short range, high splash, fire damage |
| Fire Helipad | Plasma Helicopter | Bigger, slower, longer range, explosive impact damage |

### Air Temple
| Building | Unit(s) | Notes |
|---|---|---|
| Air Factory | Hot Air Balloon | Cheap, high splash, low range, ground/naval targets only, slow |
| Hangar | 2x plane units | **Names/stats not yet defined** |

### Treehouse
| Building | Unit(s) | Notes |
|---|---|---|
| Barracks | Infantry (shared w/ Capital roster) | |
| Quad Hangar | Quad-bike | Fast, ignores forest vehicle-block, low armor/damage |

### Kraken Point
| Building | Unit(s) | Notes |
|---|---|---|
| Shipyard | Full navy roster incl. Aircraft Carrier | Aircraft Carrier can *hold* (not produce) most air troops fuel-free |

## Fuel/Maintenance Quick Reference
- Land vehicles: free while stationary, consume Fuel while moving.
- Aircraft: heavy Fuel consumption, free while stationed adjacent to a base.
- Ships: consume very little Fuel regardless of state.

## Still To Do
- [ ] Full infantry roster (Barracks)
- [ ] Full light vehicle roster (Factory)
- [ ] Full basic navy roster (Port)
- [ ] Air Temple's Hangar plane units (names + stats)
- [ ] Full Kraken Point Shipyard roster (ship tiers up to Aircraft Carrier)
- [ ] Engineer combat stats
- [ ] Commander stats/abilities
- [ ] Full stat sheet: HP, damage, speed, cost, splash radius, range for every unit
- [ ] Rock-paper-scissors matchup matrix

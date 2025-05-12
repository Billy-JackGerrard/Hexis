import { Terrain } from './hex';
import { Resource } from './resource';

/**
 * All available building types in the game
 */
export type BuildingType =
  | "empty" // nothing / not yet built
  | 'palace' // important building; only exists in home base. cant be built; only upgraded; is there from the start. if destroyed, you lose.
  | 'headquarters' // in all bases as the first/founding building, determines maximum level of other buildings. cant be built, only upgraded, as it comes with the base when a base is founded/taken
  | 'farm' // produces food
  | 'sawmill' // produces wood
  | 'mine' // produces iron
  | 'windmill' // produces energy
  | 'house' // increases population, quantity and maximum level is also dependent on food
  | 'turret' // defensive structure. can shoot bullets - has damage, range and attack speed but they're all level dependent. where do i implement this?
  | 'missile' // defensive structure. can shoot missile - has damage, range and attack speed, same as turret. this one does area damage.
  | 'factory' // produces vehicles
  ;
  


export interface Building {
    readonly id: string;
    readonly baseId: string; // id of the base that owns this building
    readonly type: BuildingType;
    level: number;
    health: number;
    lastAttack?: number; // timestamp for combat cooldown
  }
  

interface BuildingMetadata {
    // Basic Info
    displayName: string;
    description: string;
    maxLevel: number;
    palaceLevelRequired: number; // level of palace required to build this building
    
    // Health
    baseHealth: number;
    healthPerLevel: number; // Flat bonus per level (better than multiplier)
    
    // Costs
    buildCost: Partial<Record<Resource, number>>; // Cost to construct. also used for levelling up
    upgradeCostMultiplier: number; // e.g., 1.5 = 50% more per level
    
    // Combat (only for turrets/missiles)
    combatStats?: {
      baseDamage: number;
      damagePerLevel: number;
      baseRange: number; // in what measurements?
      rangePerLevel?: number;
      reloadTime: number;
      isAOE?: boolean; // maybe AOE is damage all troops in the hex, plus does 0.2x of the damage to adjacent hexes?
    };
    
    // Production (for farms/mines etc.)
    production?: {
      resource: Resource;
      baseRate: number; // Units per minute
      ratePerLevel: number; // increase of baseRate per level
    };
    
    // Placement Rules
    placement?: {
      allowedTerrain: Terrain[];
      adjacencyBonus?: {
        type: Terrain;
        bonus: number; // e.g. 1.2 means +20% production (multiplied by 1.2)
      }[];
    };
}



// possibly add validation here

import metadata from '../data/buildings.json';
export const BUILDINGS_METADATA = metadata as Record<BuildingType, BuildingMetadata>;
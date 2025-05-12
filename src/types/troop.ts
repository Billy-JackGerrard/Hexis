import { Resource } from './resource';
import { Terrain } from './hex';
import { BuildingType } from './building';

export type TroopType =
    | 'Jeep'
    ;


export interface Troop {
    readonly id: string;
    readonly type: TroopType;
    health: number;
    lastAttack?: number; // timestamp for combat cool down
    // do we include stuff like max health, speed, damage etc here?
    // they're all defined in the meta data but this troop specifically could be changed by a buff or debuff, etc
}



// these aren't done:

type TroopCategory =
    | 'infantry'
    | 'vehicle'
    // | 'aircraft'
    // | 'naval'
    // | 'special';

interface TroopCategoryMetadata {
    displayName: string;
    description: string;
    terrainMoveCosts: { // what terrains can this troop move on and what are the costs
        [key in Terrain]: number; // cost to move on this terrain (in pixels? or hexes?)
    };
    buildingType: BuildingType; // what building can this troop be produced from
    moveCostResource: Resource; // what resource is used to move this troop (either energy or food, or maybe both?)
}

interface TroopMetadata {

    // Basic Info
    displayName: string;
    description: string;
    category: TroopCategory;
    buildingLevelRequired: number; // level of building required to build this troop
    
    // Combat Stats
    health: number;

    attack?: {
        damage: number;
        range: number; // in what measurements?
        attackSpeed: number;
        isAOE?: boolean; // maybe AOE is damage all troops in the hex, plus does 0.2x of the damage to adjacent hexes?
        bonusDamage?: {
            type: 'building' | TroopCategory;
            multiplier: number; // e.g. 1.2 means +20% damage (multiplied by 1.2)
          }[]
    }

    // Costs
    buildCost: Partial<Record<Resource, number>>; // Cost to construct. also used for levelling up
    moveCost: Partial<Record<Resource, number>>; // Cost to move per hex/pixel

    // Movement
    speed: number;
}
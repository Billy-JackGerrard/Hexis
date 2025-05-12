
export type TroopType =
    | 'Jeep'
    ;

export interface Troop {
    readonly id: string;
    readonly type: TroopType;
    health: number;
    lastAttack: number; // timestamp for combat cool down
    // do we include stuff like max health, speed, damage etc here?
    // they're all defined in the meta data but this troop specifically could be changed by a buff or debuff, etc
}


interface TroopMetadata {
    // TODO
}



// possibly add validation here

import metadata from '../data/troops.json';
export const TROOP_METADATA = metadata as Record<TroopType, TroopMetadata>;
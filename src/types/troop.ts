
export type TroopType =
    | 'Jeep'
    ;

export interface Troop {
    readonly id: string;
    readonly type: TroopType;
    health: number;
    lastAttack: number; // timestamp for combat cooldown
}


interface TroopMetadata {
    // TODO
}



// possibly add validation here

import metadata from '../data/troops.json';
export const TROOP_METADATA = metadata as Record<TroopType, TroopMetadata>;
import { Resource } from "./resource";
import { BuildingType } from "./building";
import { TroopType } from "./troop";

export interface PlayerInterface {
    readonly id: string,
    username: string,
    resources: {
        [key in Resource]: number
    }
    bases: string[], // Array of base IDs
    palaceLevel: number,
    lastCollectionTime: number,

    unlockedBuildings: () => BuildingType[],
    unlockedTroops: () => TroopType[],
    gainResource: (resource: Resource, quantity: number) => void,
    loseResource: (resource: Resource, quantity: number) => void,
}
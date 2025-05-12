import { Resource } from "./resource";

export interface Base {
    readonly name: string,
    playerId: string,
    homeBase: boolean, // not sure if this is necessary
    buildingCoords: string[], // array of hex coordinates - string is in the form "q,r,s" which is the same as the key in the hex object

    // total production rates across all buildings. it's here not in player in case player loses the base
    productionRates: Record<Resource, number>; 
    
    headquartersLevel: number; // Level of the headquarters building
}
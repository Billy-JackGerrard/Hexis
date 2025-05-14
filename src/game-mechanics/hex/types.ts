
export type Terrain = 
    | 'grassland'
    | 'mountain'
    | 'forest'
    | 'desert'
    | 'ocean'
    | 'swamp'
    | 'hill'
    | 'volcano'
    | 'river';



export interface HexCoordinates {
    q: number;
    r: number;
    s: number;
}


export interface Hex {
    coords: HexCoordinates;
    // terrain: Terrain;
}
import { Building } from "./building";


// terrain types
export type Terrain =
    | 'grassland'
    | 'forest'
    | 'water'
    | 'hill'
    | 'mountain'
    | 'desert'
    // | 'swamp'
    ;

export interface HexCoordinates {
  q: number;
  r: number;
  s: number;
}


export interface Hex {
  readonly coords: HexCoordinates;
  readonly terrain: Terrain;
  base?: { baseId: string; building: Building}
  // baseId is the id of the base that owns this hex
  // building is the building that is on this hex
}
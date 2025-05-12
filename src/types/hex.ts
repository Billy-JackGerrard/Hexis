// Define a type for a hex

import { Building } from "./building";

// helper function for getting key
export function calcKey(coords: HexCoordinates) {
  return `${coords.q},${coords.r},${coords.s}`;
}


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
}
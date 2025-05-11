// Define a type for a hex

// export type HexId = `${number},${number},${number}`;

import { Building } from "./building";
import { Resource } from "./resource";

// helper function for getting key - probably wrong file to put this
export function calcKey(coords: HexCoordinates) {
  return `${coords.q},${coords.r},${coords.s}`;
}


// terrain and resources types
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
  coords: HexCoordinates;
  terrain: Terrain;
  base?: { baseId: string; building: Building}
  resource?: { type: Resource; quantity: number }
}
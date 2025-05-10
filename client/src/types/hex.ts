// Define a type for a hex

// export type HexId = `${number},${number},${number}`;

import { Building } from './building';




// helper function for getting key - probably wrong file to put this
export function calcKey(coords: HexCoordinates) {
  return `${coords.q},${coords.r},${coords.s}`;
}



export interface HexCoordinates {
  q: number;
  r: number;
  s: number;
}

// TODO
// sort these out later, all terrains resources buildings etc

export type Terrain =
    | 'grassland'
    // | 'desert'
    | 'water'
    | 'mountain'
    // | 'forest'
    // | 'swamp'
    ;

export type Resource =
    | 'iron'
    | 'wood'
    | 'energy'
    | 'food'
    ;

export interface Hex {
  coords: HexCoordinates;
  terrain: Terrain;
  base?: { baseId: string; building: Building}
  resource?: { type: Resource; quantity: number }
}


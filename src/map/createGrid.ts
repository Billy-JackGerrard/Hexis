import * as honeycomb from 'honeycomb-grid';
import { GRID_RADIUS, HEXAGON_SIZE } from '../data/config';
import { Terrain } from '../data/types';

class MapHex extends honeycomb.defineHex({ dimensions: HEXAGON_SIZE, origin: {x:0,y:0} }) {

    static create(coordinates: honeycomb.HexCoordinates, terrain: Terrain) {
      const hex = new MapHex(coordinates)
      hex.terrain = terrain;
      return hex
    }
  
    terrain!: Terrain;
  }



export default function createGrid() {

    const hexes = []
    for (let q = -GRID_RADIUS; q <= GRID_RADIUS; q++) {
        for (let r = -GRID_RADIUS; r <= GRID_RADIUS; r++) {
            let s = -q - r;

            if (
                Math.abs(q) > GRID_RADIUS ||
                Math.abs(r) > GRID_RADIUS ||
                Math.abs(s) > GRID_RADIUS
            ) continue

            const terrain: Terrain = getTerrain(q, r, s)
            hexes.push(MapHex.create({q:q,r:r,s:s}, terrain))
        }
    }

    return new honeycomb.Grid(MapHex, hexes)

}



function getTerrain(q: number, r: number, s: number): Terrain {

    // Mountains for outer tiles
    if ([Math.abs(q), Math.abs(r), Math.abs(s)].includes(GRID_RADIUS)) {
        return 'mountain'
    } else {

        // Random terrain for inner tiles
        const random = Math.random();
        if (random < 0.1) return 'forest';
        if (random < 0.15) return 'hill';
        if (random < 0.18) return 'desert';
        if (random < 0.2) return 'water';
        if (random < 0.21) return 'mountain';
        return 'grass';
    } 

}
import * as honeycomb from 'honeycomb-grid';
import { HEXAGON_QUANTITY, HEXAGON_SIZE } from '../data/config';
import { Terrain } from '../data/types';


const GRID_RADIUS = 25;

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
    for (let q = -GRID_RADIUS; q < GRID_RADIUS; q++) {
        for (let r = -GRID_RADIUS; r = GRID_RADIUS; r++) {

            const terrain: Terrain = chooseRandomTerrain(q,r)
            hexes.push(MapHex.create({q:q,r:r}, terrain))
        }
    }

    return new honeycomb.Grid(MapHex, hexes)

}



function chooseRandomTerrain(q: number, r: number): Terrain {

    if (Math.abs(q) == GRID_RADIUS || Math.abs(r) == GRID_RADIUS) {
        return 'mountain'
    } else {
        return 'grass'
    } 

}
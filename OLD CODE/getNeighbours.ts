
import { GRID_RADIUS } from "../src/data/config.ts";
import { HexCoordinates } from "../src/data/types.ts";


const directions = [
    { q: 1, r: 0, s: -1 },   // right
    { q: 1, r: -1, s: 0 },   // top-right
    { q: 0, r: -1, s: 1 },   // top-left
    { q: -1, r: 0, s: 1 },   // left
    { q: -1, r: 1, s: 0 },   // bottom-left
    { q: 0, r: 1, s: -1 },   // bottom-right
];


/**
 * 
 * @param coords 
 * @returns Coordinates of the 6 neighbouring hexes, in an array
 */
export function getHexNeighbours(coords: HexCoordinates): HexCoordinates[] {

    return directions
        .map(dir => {

            const neighbour = {
            q: coords.q + dir.q,
            r: coords.r + dir.r,
            s: coords.s + dir.s,
            };

            if (neighbour.q + neighbour.r + neighbour.s !== 0) {
                throw new Error(`Invalid cube coordinates: ${JSON.stringify(neighbour)}`);
                
            } else if (
                Math.abs(neighbour.q) > GRID_RADIUS ||
                Math.abs(neighbour.r) > GRID_RADIUS ||
                Math.abs(neighbour.s) > GRID_RADIUS
              ) {
                return null;
              }
            
            return neighbour;
        })
        .filter((n): n is HexCoordinates => n !== null);;
}
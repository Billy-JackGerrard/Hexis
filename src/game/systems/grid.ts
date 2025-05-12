import { HexCoordinates, Terrain, Hex } from "../../types";
import { GRID_RADIUS } from "../../data/config";



// Grid generation

let radius: number;


export function generateGrid() {
    return generateHexGrid(GRID_RADIUS);
}



function generateHexGrid(gridRadius: number) {
    radius = gridRadius;
    const hexes: Hex[] = [];
    
    for (let q = -radius; q <= radius; q++) {
        for (let r = -radius; r <= radius; r++) {
            const s = -q - r;
            if (Math.abs(s) > radius) continue;

            const coords = { q, r, s };
            
            hexes.push({
                coords,
                terrain: generateTerrain(coords),
                // Add other default hex properties here if needed
            });
        }
    }
    
    return hexes;
}

// gets a terrain type based on the hex's coordinates
function generateTerrain(coords: HexCoordinates) : Terrain {

    // let edge hexes be mountains
    // TODO: add more terrain types
    if (isEdgeHex(coords)) {
        return 'mountain';
    } else {
        return 'grassland';
    }
}


// helper function for calculating if hex is on the edge of the grid
function isEdgeHex(coords: HexCoordinates) : boolean {
    return [Math.abs(coords.q), Math.abs(coords.r), Math.abs(coords.s)].includes(radius);
}




// Hex neighbour calculation


const directions = [
    { q: 1, r: 0, s: -1 },  // right
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

    if (!radius) throw new Error("Grid radius not set. Please call generateGrid() first.");
    // or change code to set radius to be GRID_RADIUS or something

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
// import { HexCoordinates, Terrain, Hex } from "../../types";
import { GRID_RADIUS } from "../data/config";
import { Hex } from "../game-mechanics/hex/types";


// Hexes generation

export default function generateHexes() {

    const hexes: Hex[] = [];
    
    for (let q = -GRID_RADIUS; q <= GRID_RADIUS; q++) {
        for (let r = -GRID_RADIUS; r <= GRID_RADIUS; r++) {
            const s = -q - r;
            if (Math.abs(s) > GRID_RADIUS) continue;

            const coords = { q, r, s };
            
            hexes.push({
                coords,
                // terrain: generateTerrain(coords),
                // Add other default hex properties here if needed
            });
        }
    }
    
    return hexes;
}

/**
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


*/


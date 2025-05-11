import { HexCoordinates, Terrain, Hex } from "../../types";



export function generateGrid() {

    const RADIUS = 25; // this is the radius of the hex grid; the number of hexes from the middle
    return generateHexGrid(RADIUS);
}



function generateHexGrid(radius: number) {
    const hexes: Hex[] = [];
    
    for (let q = -radius; q <= radius; q++) {
        for (let r = -radius; r <= radius; r++) {
            const s = -q - r;
            if (Math.abs(s) > radius) continue;

            const coords = { q, r, s };
            
            hexes.push({
                coords,
                terrain: generateTerrain(coords, radius),
                // Add other default hex properties here if needed
            });
        }
    }
    
    return hexes;
}



function generateTerrain(coords: HexCoordinates, radius: number) : Terrain {

    const isEdge = [Math.abs(coords.q), Math.abs(coords.r), Math.abs(coords.s)].includes(radius);

    // let edge hexes be mountains
    if (isEdge) {
        return 'mountain';
    } else {
        return 'grassland';
    }
}

import { useGameStore } from "../../store/useGameStore";
import { HexCoordinates, Terrain } from "../../types";


export function generateHexGrid(radius: number) {

  const { addHex } = useGameStore.getState();
    
    for (let q = -radius; q <= radius; q++) {
        for (let r = -radius; r <= radius; r++) {
            const s = -q - r;
            if (Math.abs(s) > radius) continue;

            const coords = {q, r, s};

            addHex({
                coords: coords,
                terrain: generateTerrain(coords, radius),
            );
        }
    }
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
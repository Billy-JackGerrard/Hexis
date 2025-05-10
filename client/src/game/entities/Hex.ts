import { HexInterface, HexPurpose, HexCoordinates, HexResources, HexPurposeOptions } from "../../types";


export class HexEntityPoop implements HexInterface {

    public resources: HexResources;
    //public colour: string;

    constructor(
        public coords: HexCoordinates,
        public purpose: HexPurpose
    ) {
        this.resources = {
            wood: 1,
            stone: 1,
            water: 1,
            food: 1,
        }
        // this.colour =
        //             purpose === HexPurposeOptions.LAND
        //             ? 'green'
        //             : purpose === HexPurposeOptions.OBSTACLE
        //             ? 'gray'
        //             : 'pink'
    }
  
    // Business logic methods
    getNeighbors(): HexCoordinates  [] {
        const directions = [
            { q: 1, r: 0, s: -1 },  // right
            { q: 1, r: -1, s: 0 },   // top-right
            { q: 0, r: -1, s: 1 },   // top-left
            { q: -1, r: 0, s: 1 },   // left
            { q: -1, r: 1, s: 0 },   // bottom-left
            { q: 0, r: 1, s: -1 },   // bottom-right
        ];

        return directions.map(dir => ({
            q: this.coords.q + dir.q,
            r: this.coords.r + dir.r,
            s: this.coords.s + dir.s,
        }));
    }
  
    isTraversable(): boolean {
      return this.purpose === HexPurposeOptions.LAND;
    }

    get key(): string {
        return getKey(this.coords);
    }
}

export function getKey(coords: HexCoordinates) {
    return `${coords.q},${coords.r},${coords.s}`;
}
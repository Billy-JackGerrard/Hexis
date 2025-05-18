import { create } from 'zustand';

export interface GameStore {
  startTime: number;
  grid: Readonly<Record<string, Hex>>;
  bases: Record<string, Base>;
  updateHexBuilding: (coords: HexCoordinates, building: Building | null) => void;
  // getHex: (coords: HexCoordinates) => Hex | undefined;
}


// helper function for getting key
function calcKey(coords: HexCoordinates) : string {
  return `${coords.q},${coords.r},${coords.s}`;
}


/**
 * Represents the game store.
 * When using Zustand in a React component, you should never just call useGameStore() without arguments.
 * Instead, always pass a selector to get only the piece of state (or function) you need.
 * This avoids causing a re-render whenever any part of the store changes.
 */
export const useGameStore = create<GameStore>((set) => {

  // initialise hexes
  const hexes = generateGrid();

  return {
    
    /**
     * The start time of the game.
     */
    startTime: Date.now(),

    /**
     * The grid of hexes.
     */
    grid: hexes.reduce((acc, hex) => {
      acc[calcKey(hex.coords)] = hex;
      return acc;
    }, {} as Record<string, Hex>),
    
    /**
     * The bases in the game.
     */
    bases: {},

    /**
     * Changes, adds or removes the building on a hex.
     * @param coords 
     * @param building 
     * @returns 
     */  
    updateHexBuilding: (coords: HexCoordinates, building: Building | null) => set((state) => {
      const key = calcKey(coords);
      const hex = state.grid[key];

      if (!hex) return state;

      const newBase = building ? { baseId: building.baseId, building } : undefined;
      if (hex.base?.baseId === newBase?.baseId) return state;
    
      return {
        grid: {
          ...state.grid,
          [key]: { ...hex, base: newBase }
        }
      }
    }),

    // commented this out because it can only be used if the entire state is used;
    // but we're trying to use selectors which wouldn't be able to use this anyway
    // alternatively, keep it and just select it in the component
    //
    // getHex: (coords: HexCoordinates) => {
    //   const key = calcKey(coords);
    //   return get().grid[key] as Readonly<Hex>;
    // }, 
  }
});

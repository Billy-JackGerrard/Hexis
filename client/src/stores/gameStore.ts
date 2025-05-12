import { createStore, StoreApi } from 'zustand';
import { Hex, Base, calcKey } from "../types";
import { generateGrid } from '../game/systems/grid';

export interface GameStore {
  startTime: number;
  grid: Readonly<Record<string, Readonly<Hex>>>;
  bases: Record<string, Base>;
  updateHex: (key: string, updates: Partial<Omit<Hex, 'coords'>>) => void;
}

export const gameStore = createStore<GameStore>((set) => {

  // initialise hexes
  const hexes = generateGrid();

  return {
    
    startTime: Date.now(),

    grid: hexes.reduce((acc, hex) => {
      acc[calcKey(hex.coords)] = hex;
      return acc;
    }, {} as Record<string, Hex>),
    
    bases: {},
    
    updateHex: (key, updates) =>
      set((state) => {
        if (!state.grid[key]) return state;
        return {
          grid: {
            ...state.grid,
            [key]: { ...state.grid[key], ...updates }
          }
        };
      })
  }
});

import { createStore, StoreApi } from 'zustand';
import { Hex, calcKey } from "../types";
import { generateGrid } from '../game/systems/Grid';

export interface GameStore {
  grid: Readonly<Record<string, Readonly<Hex>>>;
  updateHex: (key: string, updates: Partial<Omit<Hex, 'coords'>>) => void;
}

export const gameStore = createStore<GameStore>((set) => {
  
  // initalise hexes
  const hexes = generateGrid();

  return {
    grid: hexes.reduce((acc, hex) => {
      acc[calcKey(hex.coords)] = hex;
      return acc;
    }, {} as Record<string, Hex>),
    
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

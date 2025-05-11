import { createStore, StoreApi } from 'zustand';
import { Hex, calcKey } from "../types";

export interface GameStore {
  grid: Readonly<Record<string, Readonly<Hex>>>;
  updateHex: (key: string, updates: Partial<Omit<Hex, 'coords'>>) => void;
}

export const createGameStore = (hexes: Hex[]): StoreApi<GameStore> =>
  createStore<GameStore>((set) => ({
    grid: hexes.reduce((acc, hex) => ({
      ...acc,
      [calcKey(hex.coords)]: hex
    }), {}),
    
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
  }));

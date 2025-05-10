import { create } from 'zustand';
import { Hex, calcKey } from "../types";

interface GameState {
  grid: Readonly<Record<string, Readonly<Hex>>>;
  updateHex: (key: string, updates: Partial<Omit<Hex, 'coords'>>) => void;
}

export const createGameState = (initialHexes: Hex[]) => 
  
  create<GameState>((set) => ({
    grid: initialHexes.reduce((acc, hex) => ({
      ...acc,
      [calcKey(hex.coords)]: hex
    }), {}),
    
    updateHex: (key, updates) => set((state) => ({
      grid: {
        ...state.grid,
        [key]: {
          ...state.grid[key],
          ...updates
        }
      }
    }))
  }));